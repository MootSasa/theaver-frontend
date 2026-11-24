import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../account_manager.dart';
import 'connection/connection.dart' as impl;

part 'app_database.g.dart';

/// Статус отправки сообщения
enum MessageSendStatus {
  sending, // 0 — Локально создано, отправляется
  sent, // 1 — Подтверждено сервером
  failed, // 2 — Ошибка отправки
}

/// Таблица чатов
@DataClassName('DbChat')
class Chats extends Table {
  TextColumn get chatId => text()();
  TextColumn get chatType => text()();
  TextColumn get name => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get lastMessage => text().nullable()();
  TextColumn get lastMessageTime => text().nullable()();
  TextColumn get updatedAt => text()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  TextColumn get lastSeen => text().nullable()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  TextColumn get lastMessageType => text().nullable()();
  BoolColumn get lastMessageIsRound => boolean().withDefault(const Constant(false))();
  TextColumn get lastMessageFileUrl => text().nullable()();
  TextColumn get lastMessageGroupedId => text().nullable()();
  TextColumn get otherUserId => text().nullable()();
  IntColumn get lastReadInboxMessageId =>
      integer().withDefault(const Constant(0))();
  IntColumn get lastReadOutboxMessageId =>
      integer().withDefault(const Constant(0))();
  IntColumn get pinnedMessageId => integer().nullable()();
  TextColumn get username => text().nullable()();
  BoolColumn get isPublic => boolean().withDefault(const Constant(false))();
  BoolColumn get isBot => boolean().withDefault(const Constant(false))();
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get peerCustomizationJson => text().nullable()();
  BoolColumn get showAuthorProfiles =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get signMessages =>
      boolean().withDefault(const Constant(false))();
  TextColumn get linkedChatId => text().nullable()();
  TextColumn get myRole => text().nullable()();
  TextColumn get lastMessageSenderId => text().nullable()();
  TextColumn get lastMessageSenderName => text().nullable()();
  BoolColumn get hasActiveCall =>
      boolean().withDefault(const Constant(false))();
  TextColumn get chatPermissionsJson => text().nullable()();
  TextColumn get reactionSettingsJson => text().nullable()();
  BoolColumn get hasProtectedContent =>
      boolean().withDefault(const Constant(false))();
  TextColumn get pinnedMessageIdsJson => text().nullable()();
  IntColumn get messageAutoDeleteTime =>
      integer().withDefault(const Constant(0))();
  TextColumn get appearanceJson => text().nullable()();
  BoolColumn get isForum => boolean().withDefault(const Constant(false))();
  BoolColumn get participantsHidden =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get hasAggressiveAntiSpamEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get maxReactionsPerPost =>
      integer().withDefault(const Constant(11))();
  IntColumn get unreadMentionsCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get unreadReactionsCount =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {chatId};
}

/// Таблица сообщений
@DataClassName('DbMessage')
class Messages extends Table {
  TextColumn get localId => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get chatId => text()();
  TextColumn get senderId => text()();
  TextColumn get content => text()();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  TextColumn get fileUrl => text().nullable()();
  TextColumn get fileName => text().nullable()();
  // Reply / Quote fields
  TextColumn get replyToMessageId => text().nullable()();
  BoolColumn get isQuote => boolean().withDefault(const Constant(false))();
  TextColumn get quoteText => text().nullable()();
  IntColumn get quoteOffset => integer().withDefault(const Constant(0))();
  IntColumn get quoteLength => integer().withDefault(const Constant(0))();
  // Cached reply preview data (for offline-first display without lookup)
  TextColumn get replyToSenderId => text().nullable()();
  TextColumn get replyToSenderName => text().nullable()();
  TextColumn get replyToContent => text().nullable()();
  TextColumn get replyToMessageType =>
      text().withDefault(const Constant('text'))();
  // Standard fields
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isEdited => boolean().withDefault(const Constant(false))();
  IntColumn get sendStatus => integer().withDefault(const Constant(1))();
  TextColumn get senderName => text().nullable()();
  TextColumn get senderAvatarUrl => text().nullable()();
  TextColumn get createdAt => text()();

  // Forwarding fields
  BoolColumn get isForward => boolean().withDefault(const Constant(false))();
  TextColumn get forwardFromId => text().nullable()();
  TextColumn get forwardFromName => text().nullable()();
  TextColumn get forwardFromAvatarUrl => text().nullable()();
  TextColumn get senderCustomizationJson => text().nullable()();

  // Entities & Album grouping
  TextColumn get groupedId => text().nullable()();
  TextColumn get entities => text().nullable()(); // JSON string of List<MessageEntity>

  // Reactions JSON string
  TextColumn get reactions => text().nullable()();

  // Link preview options & media caption position
  TextColumn get linkPreviewOptions => text().nullable()(); // JSON string of LinkPreviewOptions
  BoolColumn get invertMedia => boolean().withDefault(const Constant(false))();

  // Round video note flag
  BoolColumn get isRound => boolean().withDefault(const Constant(false))();

  // Dedicated media payload (waveform, duration, thumb, metadata)
  TextColumn get mediaPayload => text().nullable()();

  // Channel posts, views, signatures, anonymous admins, silent posts & comments
  IntColumn get viewsCount => integer().withDefault(const Constant(0))();
  TextColumn get authorSignature => text().nullable()();
  TextColumn get postAuthorId => text().nullable()();
  TextColumn get senderRole => text().nullable()();
  TextColumn get senderAdminTitle => text().nullable()();
  BoolColumn get isFromAnonymousAdmin =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isSilent => boolean().withDefault(const Constant(false))();
  IntColumn get commentsCount => integer().withDefault(const Constant(0))();
  TextColumn get recentRepliersJson => text().nullable()();
  TextColumn get threadRootMessageId => text().nullable()();
  BoolColumn get hasMediaSpoiler =>
      boolean().withDefault(const Constant(false))();
  TextColumn get expiresAt => text().nullable()();
  IntColumn get ttlSeconds => integer().withDefault(const Constant(0))();
  BoolColumn get isViewOnce => boolean().withDefault(const Constant(false))();
  TextColumn get viewedAt => text().nullable()();
  BoolColumn get isBurned => boolean().withDefault(const Constant(false))();
  TextColumn get replyToChatId => text().nullable()();
  TextColumn get replyToChatName => text().nullable()();
  TextColumn get replyToChatType => text().nullable()();
  TextColumn get effectId => text().nullable()();
  TextColumn get savedTagsJson => text().nullable()();
  IntColumn get topicId => integer().nullable()();
  IntColumn get forwardsCount => integer().withDefault(const Constant(0))();
  TextColumn get senderChatId => text().nullable()();
  TextColumn get senderChatName => text().nullable()();
  TextColumn get senderChatAvatarUrl => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Таблица состояния синхронизации
@DataClassName('DbSyncState')
class SyncStates extends Table {
  TextColumn get userId => text()();
  IntColumn get lastKnownUsn => integer().withDefault(const Constant(0))();
  TextColumn get lastSyncAt => text()();

  @override
  Set<Column> get primaryKey => {userId};
}

/// Таблица банковских карт
@DataClassName('DbBankingCard')
class BankingCards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cardId => text()();
  TextColumn get cardNumber => text()();
  TextColumn get cardHolder => text()();
  TextColumn get expiryDate => text()();
  TextColumn get cardType => text()();
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();
}

/// Локальная база данных на Drift (SQLite).
/// Заменяет IsarDatabaseService для Offline-First архитектуры.
@DriftDatabase(tables: [Chats, Messages, SyncStates, BankingCards])
class AppDatabase extends _$AppDatabase {
  static final Map<String, AppDatabase> _instances = {};
  static String? _activeUserId;

  /// Set the currently active user ID for global AppDatabase() resolution
  static void setActiveUser(String? userId) {
    _activeUserId = userId;
  }

  /// Resolve current active user ID (from explicit setting or AccountManager)
  static String get activeUserId {
    return _activeUserId ?? AccountManager().currentAccount?.userId ?? 'default';
  }

  /// Factory constructor returning the database instance for [userId] (or active user)
  factory AppDatabase([String? userId]) {
    final uid = (userId != null && userId.isNotEmpty)
        ? userId
        : activeUserId;
    return _instances.putIfAbsent(uid, () => AppDatabase._internal(uid));
  }

  /// The user ID this database instance belongs to
  final String userId;

  AppDatabase._internal(this.userId) : super(_openConnection(userId));

  @visibleForTesting
  AppDatabase.forTesting(QueryExecutor executor, {this.userId = 'test'})
      : super(executor);

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static QueryExecutor _openConnection(String userId) {
    final dbName = (userId.isNotEmpty && userId != 'default')
        ? 'theaver_$userId'
        : 'theaver';
    return impl.openConnection(dbName);
  }

  /// Removes and closes a specific user database and deletes its file
  static Future<void> removeUserDatabase(String userId) async {
    if (_instances.containsKey(userId)) {
      final db = _instances.remove(userId)!;
      try {
        await db.close();
      } catch (_) {}
    }
    final dbName = (userId.isNotEmpty && userId != 'default')
        ? 'theaver_$userId'
        : 'theaver';
    try {
      await impl.deleteDatabaseFile(dbName);
    } catch (_) {}
  }

  /// Close all open database instances
  static Future<void> closeAll() async {
    for (final db in _instances.values) {
      try {
        await db.close();
      } catch (_) {}
    }
    _instances.clear();
  }

  /// Closes all open database instances and deletes all database files on disk
  static Future<void> deleteAllDatabases() async {
    await closeAll();
    try {
      await impl.deleteAllDatabaseFiles();
    } catch (_) {}
  }

  Future<void> _addColumnIfMissing(
    String tableName,
    String columnName,
    String sqlDefinition,
  ) async {
    final cols = await customSelect('PRAGMA table_info($tableName)').get();
    final exists = cols.any((row) => row.data['name'] == columnName);
    if (!exists) {
      await customStatement(
        'ALTER TABLE $tableName ADD COLUMN $columnName $sqlDefinition',
      );
    }
  }

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // Создать индексы
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON messages(chat_id, created_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_server_id ON messages(server_id) WHERE server_id IS NOT NULL',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_grouped_id ON messages(grouped_id) WHERE grouped_id IS NOT NULL',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_thread_root ON messages(chat_id, thread_root_message_id, created_at) WHERE thread_root_message_id IS NOT NULL',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_messages_chat_topic ON messages(chat_id, topic_id, created_at) WHERE topic_id IS NOT NULL',
          );
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // V2: Add reply/quote fields
            await customStatement(
              'ALTER TABLE messages ADD COLUMN is_quote INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN quote_text TEXT',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN quote_offset INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN quote_length INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN reply_to_sender_id TEXT',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN reply_to_sender_name TEXT',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN reply_to_content TEXT',
            );
            await customStatement(
              "ALTER TABLE messages ADD COLUMN reply_to_message_type TEXT NOT NULL DEFAULT 'text'",
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL',
            );
          }
          if (from < 3) {
            await m.createTable(bankingCards);
          }
          if (from < 4) {
            await customStatement(
              'ALTER TABLE messages ADD COLUMN grouped_id TEXT',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN entities TEXT',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_messages_grouped_id ON messages(grouped_id) WHERE grouped_id IS NOT NULL',
            );
          }
          if (from < 5) {
            await customStatement(
              'ALTER TABLE messages ADD COLUMN reactions TEXT',
            );
          }
          if (from < 6) {
            await customStatement(
              'ALTER TABLE messages ADD COLUMN link_preview_options TEXT',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN invert_media INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 7) {
            await customStatement(
              'ALTER TABLE messages ADD COLUMN is_round INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 8) {
            await customStatement(
              'ALTER TABLE messages ADD COLUMN media_payload TEXT',
            );
          }
          if (from < 9) {
            await customStatement(
              'ALTER TABLE chats ADD COLUMN last_message_type TEXT',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN last_message_is_round INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN last_message_file_url TEXT',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN last_message_grouped_id TEXT',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN other_user_id TEXT',
            );
          }
          if (from < 10) {
            await customStatement(
              'ALTER TABLE chats ADD COLUMN last_read_inbox_message_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN last_read_outbox_message_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN pinned_message_id INTEGER',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN username TEXT',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN is_verified INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 11) {
            await customStatement(
              'ALTER TABLE chats ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 12) {
            await customStatement(
              'ALTER TABLE chats ADD COLUMN peer_customization_json TEXT',
            );
            await customStatement(
              'ALTER TABLE chats ADD COLUMN show_author_profiles INTEGER NOT NULL DEFAULT 1',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN forward_from_avatar_url TEXT',
            );
            await customStatement(
              'ALTER TABLE messages ADD COLUMN sender_customization_json TEXT',
            );
          }
          if (from < 13) {
            await _addColumnIfMissing(
              'chats',
              'sign_messages',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('chats', 'linked_chat_id', 'TEXT');
            await _addColumnIfMissing('chats', 'my_role', 'TEXT');
            await _addColumnIfMissing('chats', 'last_message_sender_id', 'TEXT');
            await _addColumnIfMissing('chats', 'last_message_sender_name', 'TEXT');
            await _addColumnIfMissing(
              'chats',
              'has_active_call',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('chats', 'chat_permissions_json', 'TEXT');
            await _addColumnIfMissing('chats', 'reaction_settings_json', 'TEXT');
            await customStatement(
              "UPDATE chats SET show_author_profiles = 0 WHERE chat_type = 'channel'",
            );

            await _addColumnIfMissing(
              'messages',
              'views_count',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('messages', 'author_signature', 'TEXT');
            await _addColumnIfMissing('messages', 'post_author_id', 'TEXT');
            await _addColumnIfMissing('messages', 'sender_role', 'TEXT');
            await _addColumnIfMissing('messages', 'sender_admin_title', 'TEXT');
            await _addColumnIfMissing(
              'messages',
              'is_from_anonymous_admin',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'messages',
              'is_silent',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'messages',
              'comments_count',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('messages', 'recent_repliers_json', 'TEXT');
            await _addColumnIfMissing('messages', 'thread_root_message_id', 'TEXT');

            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_messages_thread_root ON messages(chat_id, thread_root_message_id, created_at) WHERE thread_root_message_id IS NOT NULL',
            );
          }
          if (from < 14) {
            await _addColumnIfMissing(
              'chats',
              'has_protected_content',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'chats',
              'pinned_message_ids_json',
              'TEXT',
            );
            await _addColumnIfMissing(
              'messages',
              'has_media_spoiler',
              'INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (from < 15) {
            await _addColumnIfMissing(
              'chats',
              'message_auto_delete_time',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('chats', 'appearance_json', 'TEXT');
            await _addColumnIfMissing('messages', 'expires_at', 'TEXT');
            await _addColumnIfMissing(
              'messages',
              'ttl_seconds',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'messages',
              'is_view_once',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('messages', 'viewed_at', 'TEXT');
            await _addColumnIfMissing(
              'messages',
              'is_burned',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('messages', 'reply_to_chat_id', 'TEXT');
            await _addColumnIfMissing('messages', 'reply_to_chat_name', 'TEXT');
            await _addColumnIfMissing('messages', 'reply_to_chat_type', 'TEXT');
            await _addColumnIfMissing('messages', 'effect_id', 'TEXT');
            await _addColumnIfMissing('messages', 'saved_tags_json', 'TEXT');
          }
          if (from < 16) {
            await _addColumnIfMissing(
              'chats',
              'is_forum',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'chats',
              'participants_hidden',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'chats',
              'has_aggressive_anti_spam_enabled',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'chats',
              'max_reactions_per_post',
              'INTEGER NOT NULL DEFAULT 11',
            );
            await _addColumnIfMissing(
              'chats',
              'unread_mentions_count',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing(
              'chats',
              'unread_reactions_count',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('messages', 'topic_id', 'INTEGER');
            await _addColumnIfMissing(
              'messages',
              'forwards_count',
              'INTEGER NOT NULL DEFAULT 0',
            );
            await _addColumnIfMissing('messages', 'sender_chat_id', 'TEXT');
            await _addColumnIfMissing('messages', 'sender_chat_name', 'TEXT');
            await _addColumnIfMissing(
              'messages',
              'sender_chat_avatar_url',
              'TEXT',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_messages_chat_topic ON messages(chat_id, topic_id, created_at) WHERE topic_id IS NOT NULL',
            );
          }
        },
      );

  /// Инициализация (открыть соединение)
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await customSelect('SELECT 1').getSingle();
      _isInitialized = true;
      debugPrint('AppDatabase: Initialized');

      // 1. Очистка пустых приватных чатов-«призраков» (без сообщений/медиа/даты, не закреплены, без непрочитанных, пустое имя)
      try {
        await customStatement(
          "DELETE FROM chats WHERE chat_type = 'private' "
          "AND (name = '' OR name = '?' OR name IS NULL) "
          "AND (last_message IS NULL OR last_message = '') "
          "AND (last_message_type IS NULL OR last_message_type = '') "
          "AND (last_message_file_url IS NULL OR last_message_file_url = '') "
          "AND (last_message_time IS NULL OR last_message_time = '') "
          "AND (is_pinned IS NULL OR is_pinned = 0) "
          "AND (unread_count IS NULL OR unread_count = 0)",
        );
        await customStatement(
          "UPDATE chats SET name = 'Пользователь' WHERE (name = '' OR name = '?' OR name IS NULL) AND chat_type = 'private'",
        );
      } catch (_) {}

      // 2. Дедупликация чатов «Избранное»
      try {
        await _cleanupDuplicateSavedChats();
      } catch (_) {}

      // 3. Очистка поврежденных сообщений без chat_id и дубликатов по server_id
      try {
        await customStatement("DELETE FROM messages WHERE chat_id = '' OR chat_id IS NULL");
        await customStatement(
          "DELETE FROM messages WHERE server_id IS NOT NULL AND server_id != '' "
          "AND rowid NOT IN (SELECT MAX(rowid) FROM messages WHERE server_id IS NOT NULL AND server_id != '' GROUP BY server_id)",
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('AppDatabase initialize error: $e');
    }
  }

  /// Убедиться, что БД инициализирована
  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // === ЧАТЫ ===

  /// Реактивный стрим чатов с сортировкой:
  /// 1) Избранное (saved) в самом верху
  /// 2) Закрепленные (isPinned == true)
  /// 3) По дате последнего сообщения / обновления (updatedAt DESC)
  Stream<List<DbChat>> watchChats({int filter = 0, bool includeArchived = false}) {
    final query = select(chats);
    // Исключаем сообщества и каналы сообществ из общего списка чатов
    query.where((t) =>
        t.chatType.isNotValue('community') &
        t.chatType.isNotValue('community_channel'));
    if (!includeArchived) {
      query.where((t) => t.isArchived.equals(false));
    }
    // Скрываем пустые приватные чаты-«призраки» (сохраняем чаты с текстом, медиа без подписи, датой, закрепом или непрочитанными)
    query.where((t) =>
        t.chatType.isNotValue('private') |
        t.isPinned.equals(true) |
        t.unreadCount.isNotValue(0) |
        (t.lastMessage.isNotNull() & t.lastMessage.isNotValue('')) |
        (t.lastMessageType.isNotNull() & t.lastMessageType.isNotValue('')) |
        (t.lastMessageFileUrl.isNotNull() & t.lastMessageFileUrl.isNotValue('')) |
        (t.lastMessageTime.isNotNull() & t.lastMessageTime.isNotValue('')));

    if (filter == 1) {
      // Личные чаты (private и saved)
      query.where((t) => t.chatType.equals('private') | t.chatType.equals('saved'));
    } else if (filter == 2) {
      // Группы (и saved)
      query.where((t) => t.chatType.equals('group') | t.chatType.equals('saved'));
    } else if (filter == 3) {
      // Каналы (и saved)
      query.where((t) => t.chatType.equals('channel') | t.chatType.equals('saved'));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.chatType.equals('saved'), mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// Поиск по локальным чатам через SQLite
  Future<List<DbChat>> searchLocalChats(String query) async {
    await ensureInitialized();
    final pattern = '%$query%';
    return (select(chats)
          ..where((t) =>
              (t.name.like(pattern) | t.lastMessage.like(pattern)) &
              t.chatType.isNotValue('community') &
              t.chatType.isNotValue('community_channel'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.chatType.equals('saved'), mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Реактивный подсчёт общего числа непрочитанных сообщений
  Stream<int> watchTotalUnread() {
    final sumCol = chats.unreadCount.sum();
    final query = selectOnly(chats)
      ..addColumns([sumCol])
      ..where(chats.chatType.isNotValue('community') & chats.chatType.isNotValue('community_channel'));
    return query.watchSingleOrNull().map((row) => row?.read(sumCol) ?? 0);
  }

  /// Получить все чаты, отсортированные по updatedAt (убывание)
  Future<List<DbChat>> getChats() async {
    await ensureInitialized();
    return (select(chats)
          ..where((t) =>
              t.chatType.isNotValue('community') &
              t.chatType.isNotValue('community_channel'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.chatType.equals('saved'), mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Реактивный поток архивированных чатов
  Stream<List<DbChat>> watchArchivedChats() {
    final query = select(chats)
      ..where((t) =>
          t.isArchived.equals(true) &
          t.chatType.isNotValue('community') &
          t.chatType.isNotValue('community_channel'))
      ..orderBy([
        (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// Получить все архивированные чаты
  Future<List<DbChat>> getArchivedChats() async {
    await ensureInitialized();
    return (select(chats)
          ..where((t) =>
              t.isArchived.equals(true) &
              t.chatType.isNotValue('community') &
              t.chatType.isNotValue('community_channel'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Обновить статус архивирования чата
  Future<void> setChatArchived(String chatId, bool archived) async {
    await ensureInitialized();
    final existing = await getChat(chatId);
    final companion = (existing != null && existing.isArchived == archived)
        ? ChatsCompanion(isArchived: Value(archived))
        : ChatsCompanion(
            isArchived: Value(archived),
            isPinned: const Value(false),
          );
    await (update(chats)..where((t) => t.chatId.equals(chatId)))
        .write(companion);
  }

  /// Получить чат по server chatId
  Future<DbChat?> getChat(String chatId) async {
    await ensureInitialized();
    return (select(chats)
          ..where((t) => t.chatId.equals(chatId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Сохранить/обновить чат (upsert)
  Future<void> saveChat(ChatsCompanion chat) async {
    await ensureInitialized();
    await into(chats).insertOnConflictUpdate(chat);
  }

  /// Сохранить список чатов (batch upsert)
  Future<void> saveChats(List<ChatsCompanion> chatCompanions) async {
    await ensureInitialized();
    await batch((b) {
      b.insertAllOnConflictUpdate(chats, chatCompanions);
    });
    if (chatCompanions.any((c) => c.chatType.value == 'saved')) {
      await _cleanupDuplicateSavedChats();
    }
  }

  /// Удалить чат по server chatId
  Future<void> deleteChat(String chatId) async {
    await ensureInitialized();
    await (delete(chats)..where((t) => t.chatId.equals(chatId))).go();
  }

  /// Обновить unread count для чата с гарантированным оповещением реактивных стримов Drift
  Future<void> updateUnreadCount(String chatId, int count) async {
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId)))
        .write(ChatsCompanion(unreadCount: Value(count)));
  }

  /// Пакетное закрепление / открепление чатов
  Future<void> batchSetPinned(List<String> chatIds, bool isPinned) async {
    if (chatIds.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.isIn(chatIds)))
        .write(ChatsCompanion(isPinned: Value(isPinned)));
  }

  /// Пакетная отметка чатов как прочитанные
  Future<void> batchMarkAsRead(List<String> chatIds) async {
    if (chatIds.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.isIn(chatIds)))
        .write(const ChatsCompanion(unreadCount: Value(0)));
  }

  /// Пакетное перемещение чатов в архив или из архива со сбросом закрепа
  Future<void> batchSetArchived(List<String> chatIds, bool archived) async {
    if (chatIds.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.isIn(chatIds))).write(
      ChatsCompanion(
        isArchived: Value(archived),
        isPinned: const Value(false),
      ),
    );
  }

  /// Пакетная отметка чатов как непрочитанные
  Future<void> batchMarkAsUnread(List<String> chatIds) async {
    if (chatIds.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.isIn(chatIds)))
        .write(const ChatsCompanion(unreadCount: Value(-1)));
  }

  /// Пакетное удаление чатов и их сообщений
  Future<void> batchDeleteChats(List<String> chatIds) async {
    if (chatIds.isEmpty) return;
    await ensureInitialized();
    await batch((b) {
      b.deleteWhere(chats, (t) => t.chatId.isIn(chatIds));
      b.deleteWhere(messages, (t) => t.chatId.isIn(chatIds));
    });
  }

  /// Обновить последнее сообщение чата и updatedAt
  Future<void> updateChatLastMessage({
    required String chatId,
    required String content,
    required String createdAt,
    String messageType = 'text',
    bool isRound = false,
    String? fileUrl,
    String? groupedId,
    String? senderId,
    String? senderName,
    bool incrementUnread = false,
  }) async {
    await ensureInitialized();
    final existing = await getChat(chatId);
    if (existing == null) return;
    final baseUnread = existing.unreadCount < 0 ? 0 : existing.unreadCount;
    final newUnread = incrementUnread ? baseUnread + 1 : existing.unreadCount;
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        lastMessage: Value(content),
        lastMessageTime: Value(createdAt),
        lastMessageType: Value(messageType),
        lastMessageIsRound: Value(isRound),
        lastMessageFileUrl: Value(fileUrl),
        lastMessageGroupedId: Value(groupedId),
        lastMessageSenderId:
            senderId != null ? Value(senderId) : const Value.absent(),
        lastMessageSenderName:
            senderName != null ? Value(senderName) : const Value.absent(),
        updatedAt: Value(createdAt),
        unreadCount: Value(newUnread),
      ),
    );
  }

  /// Пересчитать последнее сообщение чата на основе последней записи в таблице сообщений.
  /// При отсутствии локальных сообщений НЕ затирает existing.lastMessage, если не передан allowClear: true.
  Future<void> refreshChatLastMessageFromDb(String chatId, {bool allowClear = false}) async {
    await ensureInitialized();
    final lastMsg = await getLastMessageForChat(chatId);
    final existing = await getChat(chatId);
    if (existing == null) return;

    if (lastMsg != null) {
      final isRound = lastMsg.isRound || lastMsg.messageType == 'round';
      await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
        ChatsCompanion(
          lastMessage: Value(lastMsg.content),
          lastMessageTime: Value(lastMsg.createdAt),
          lastMessageType: Value(lastMsg.messageType),
          lastMessageIsRound: Value(isRound),
          lastMessageFileUrl: Value(lastMsg.fileUrl),
          lastMessageGroupedId: Value(lastMsg.groupedId),
          lastMessageSenderId: Value(lastMsg.senderId),
          lastMessageSenderName: Value(lastMsg.senderName),
          updatedAt: Value(lastMsg.createdAt),
        ),
      );
    } else if (allowClear) {
      await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
        const ChatsCompanion(
          lastMessage: Value(null),
          lastMessageTime: Value(null),
          lastMessageType: Value(null),
          lastMessageIsRound: Value(false),
          lastMessageFileUrl: Value(null),
          lastMessageGroupedId: Value(null),
          lastMessageSenderId: Value(null),
          lastMessageSenderName: Value(null),
        ),
      );
    }
  }

  /// Частичное обновление чата (только переданные поля)
  Future<void> updateChat(String chatId, ChatsCompanion companion) async {
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId)))
        .write(companion);
  }

  /// Обновить аватар чата по chatId
  Future<void> updateChatAvatar(String chatId, String? avatarUrl) async {
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId)))
        .write(ChatsCompanion(avatarUrl: Value(avatarUrl)));
  }

  /// Обновить аватар пользователя в чатах и сообщениях
  Future<void> updateUserAvatarInChats(String userId, String? avatarUrl) async {
    await ensureInitialized();
    await (update(chats)
          ..where((t) =>
              t.chatType.equals('private') & t.otherUserId.equals(userId)))
        .write(ChatsCompanion(avatarUrl: Value(avatarUrl)));
    await (update(messages)..where((t) => t.senderId.equals(userId)))
        .write(MessagesCompanion(senderAvatarUrl: Value(avatarUrl)));
  }

  /// Обновить статус онлайн и время последнего визита собеседника во всех личных чатах с этим пользователем
  Future<void> updateUserStatus(
    String userId, {
    required bool isOnline,
    String? lastSeen,
  }) async {
    if (userId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)
          ..where((t) =>
              t.chatType.equals('private') & t.otherUserId.equals(userId)))
        .write(
      ChatsCompanion(
        isOnline: Value(isOnline),
        lastSeen: lastSeen != null
            ? Value(lastSeen)
            : (isOnline ? const Value.absent() : Value(DateTime.now().toIso8601String())),
      ),
    );
  }

  /// Обновить статус онлайн, время последнего визита и otherUserId для конкретного личного чата
  Future<void> updateChatPresence(
    String chatId, {
    String? otherUserId,
    required bool isOnline,
    String? lastSeen,
  }) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        otherUserId: otherUserId != null && otherUserId.isNotEmpty
            ? Value(otherUserId)
            : const Value.absent(),
        isOnline: Value(isOnline),
        lastSeen: Value(lastSeen),
      ),
    );
  }

  /// Дедупликация чатов "Избранное": оставляет один канонический чат, переносит сообщения и удаляет дубликаты
  Future<void> _cleanupDuplicateSavedChats([String? userId]) async {
    final savedChatsList = await (select(chats)..where((t) => t.chatType.equals('saved'))).get();
    if (savedChatsList.length <= 1) return;

    // Предпочитаем серверный ID (не начинающийся на 'saved_') как канонический
    final canonicalChat = savedChatsList.firstWhere(
      (c) => !c.chatId.startsWith('saved_'),
      orElse: () => savedChatsList.first,
    );

    for (final c in savedChatsList) {
      if (c.chatId != canonicalChat.chatId) {
        // Переносим сообщения на канонический чат
        await customStatement(
          'UPDATE messages SET chat_id = ? WHERE chat_id = ?',
          [canonicalChat.chatId, c.chatId],
        );
        // Удаляем лишнюю запись чата
        await (delete(chats)..where((t) => t.chatId.equals(c.chatId))).go();
      }
    }
    debugPrint('AppDatabase: Cleaned up duplicate saved chats, kept ${canonicalChat.chatId}');
  }

  /// Убедиться, что чат "Избранное" существует локально
  Future<void> ensureSavedChatExists(String userId) async {
    await ensureInitialized();
    await _cleanupDuplicateSavedChats(userId);
    final existing = await (select(chats)..where((t) => t.chatType.equals('saved'))).get();
    final mgr = AccountManager();
    final account = (mgr.currentAccount?.userId == userId ? mgr.currentAccount : null) ??
        mgr.accounts.where((acc) => acc.userId == userId).firstOrNull ??
        mgr.currentAccount;
    if (existing.isEmpty) {
      await saveChat(ChatsCompanion(
        chatId: Value('saved_$userId'),
        chatType: const Value('saved'),
        name: const Value('Избранное'),
        avatarUrl: Value(account?.avatarUrl),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ));
      debugPrint('AppDatabase: Created local "Saved Messages" chat for $userId');
    } else if (account?.avatarUrl != null && account!.avatarUrl!.isNotEmpty) {
      final first = existing.first;
      if (first.avatarUrl == null || first.avatarUrl!.isEmpty) {
        await (update(chats)..where((t) => t.chatId.equals(first.chatId))).write(
          ChatsCompanion(avatarUrl: Value(account.avatarUrl)),
        );
      }
    }
  }

  /// Миграция локального chatId Избранного при получении серверного chatId
  Future<void> migrateSavedChatId(String localSavedId, String serverSavedId) async {
    if (localSavedId == serverSavedId) return;
    await ensureInitialized();

    // Сначала переносим сообщения
    await customStatement(
      'UPDATE messages SET chat_id = ? WHERE chat_id = ?',
      [serverSavedId, localSavedId],
    );

    // Проверяем, существует ли уже серверный чат в базе
    final serverChat = await (select(chats)
          ..where((t) => t.chatId.equals(serverSavedId))
          ..limit(1))
        .getSingleOrNull();
    if (serverChat != null) {
      // Серверный чат уже вставлен, удаляем локальный плейсхолдер во избежание дубликатов
      await (delete(chats)..where((t) => t.chatId.equals(localSavedId))).go();
    } else {
      // Серверного чата еще нет, переименовываем локальный плейсхолдер
      await customStatement(
        'UPDATE chats SET chat_id = ? WHERE chat_id = ?',
        [serverSavedId, localSavedId],
      );
    }
    await _cleanupDuplicateSavedChats();
  }

  // === СООБЩЕНИЯ ===

  /// Получить сообщения чата с пагинацией (исключая комментарии тредов по умолчанию)
  /// [beforeCreatedAt] — курсор (ISO 8601), загружать сообщения старше этого
  /// [limit] — количество
  Future<List<DbMessage>> getMessages(
    String chatId, {
    String? beforeCreatedAt,
    int limit = 50,
    bool includeThreadComments = false,
    int? topicId,
  }) async {
    await ensureInitialized();
    final stmt = select(messages);
    stmt.where((t) {
      Expression<bool> cond = t.chatId.equals(chatId);
      if (topicId != null) {
        cond = cond & t.topicId.equals(topicId);
      }
      if (!includeThreadComments) {
        cond = cond &
            (t.threadRootMessageId.isNull() | t.threadRootMessageId.equals(''));
      }
      if (beforeCreatedAt != null) {
        cond = cond & t.createdAt.isSmallerThanValue(beforeCreatedAt);
      }
      return cond;
    });
    stmt.orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.localId),
    ]);
    stmt.limit(limit);
    return stmt.get();
  }

  /// Получить сообщения чата (алиас с опциональным фильтром по теме форума)
  Future<List<DbMessage>> getMessagesForChat(
    String chatId, {
    String? beforeCreatedAt,
    int limit = 50,
    bool includeThreadComments = false,
    int? topicId,
  }) =>
      getMessages(
        chatId,
        beforeCreatedAt: beforeCreatedAt,
        limit: limit,
        includeThreadComments: includeThreadComments,
        topicId: topicId,
      );

  /// Реактивный поток сообщений основной ленты чата (включая зеркалированные посты канала, но без комментариев внутри тредов)
  Stream<List<DbMessage>> watchMessagesForChat(
    String chatId, {
    int limit = 50,
    bool includeThreadComments = false,
    int? topicId,
  }) {
    final stmt = select(messages)
      ..where((t) {
        Expression<bool> cond = t.chatId.equals(chatId);
        if (topicId != null) {
          cond = cond & t.topicId.equals(topicId);
        }
        if (!includeThreadComments) {
          cond = cond &
              (t.threadRootMessageId.isNull() |
                  t.threadRootMessageId.equals(''));
        }
        return cond;
      })
      ..orderBy([
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.desc(t.localId),
      ])
      ..limit(limit);
    return stmt.watch();
  }

  /// Реактивный поток комментариев под постом канала в группе обсуждения
  Stream<List<DbMessage>> watchThreadComments(
    String chatId,
    String rootMessageId, {
    int limit = 100,
  }) {
    final stmt = select(messages)
      ..where((t) =>
          t.chatId.equals(chatId) &
          t.threadRootMessageId.equals(rootMessageId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.localId),
      ])
      ..limit(limit);
    return stmt.watch();
  }

  /// Получить комментарии к посту канала в группе обсуждения
  Future<List<DbMessage>> getThreadComments(
    String chatId,
    String rootMessageId, {
    int limit = 100,
  }) async {
    await ensureInitialized();
    return (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              t.threadRootMessageId.equals(rootMessageId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.localId),
          ])
          ..limit(limit))
        .get();
  }

  /// Получить сообщение по localId
  Future<DbMessage?> getMessageByLocalId(String localId) async {
    await ensureInitialized();
    return (select(messages)
          ..where((t) => t.localId.equals(localId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Получить сообщение по serverId
  Future<DbMessage?> getMessageByServerId(String serverId) async {
    await ensureInitialized();
    return (select(messages)
          ..where((t) => t.serverId.equals(serverId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Сохранить сообщение (upsert по localId — primary key)
  /// Если у сообщения есть serverId, сначала проверяет существующую запись
  /// по serverId и переиспользует её localId для корректного обновления
  Future<void> saveMessage(MessagesCompanion message) async {
    await ensureInitialized();
    // Если есть serverId (не absent и не null), проверить существующее сообщение
    final serverIdValue = message.serverId;
    final hasServerId = serverIdValue.present &&
        serverIdValue.value != null &&
        serverIdValue.value!.isNotEmpty;
    if (hasServerId) {
      final sid = serverIdValue.value!;
      final existingMatches = await (select(messages)
            ..where((t) => t.serverId.equals(sid) | t.localId.equals(sid)))
          .get();
      if (existingMatches.isNotEmpty) {
        final canonical = existingMatches.first;
        if (existingMatches.length > 1) {
          final duplicateLocalIds = existingMatches
              .skip(1)
              .map((m) => m.localId)
              .toList();
          await (delete(messages)
                ..where((t) => t.localId.isIn(duplicateLocalIds)))
              .go();
        }
        // Переиспользовать существующий localId для корректного upsert
        await into(messages).insertOnConflictUpdate(
          message.copyWith(localId: Value(canonical.localId)),
        );
        return;
      }
    }
    await into(messages).insertOnConflictUpdate(message);
  }

  /// Сохранить список сообщений (batch upsert с проверкой serverId)
  Future<void> saveMessages(List<MessagesCompanion> messageCompanions) async {
    await ensureInitialized();
    for (final message in messageCompanions) {
      await saveMessage(message);
    }
  }

  /// Обновить статус отправки: заменить localId на serverId
  Future<void> updateMessageSendStatus(
      String localId, String serverId, int status,
      {String? fileUrl}) async {
    await ensureInitialized();
    if (serverId.isNotEmpty) {
      // Удаляем возможный дубликат, если сообщение уже успело прийти по WebSocket/Sync с localId == serverId
      await (delete(messages)
            ..where((t) =>
                t.localId.isNotValue(localId) &
                (t.serverId.equals(serverId) | t.localId.equals(serverId))))
          .go();
    }
    await (update(messages)..where((t) => t.localId.equals(localId)))
        .write(MessagesCompanion(
      serverId: Value(serverId),
      sendStatus: Value(status),
      fileUrl: fileUrl != null ? Value(fileUrl) : const Value.absent(),
    ));
  }

  /// Обновить только статус отправки (без serverId)
  Future<void> updateMessageStatus(String localId, int status) async {
    await ensureInitialized();
    await (update(messages)..where((t) => t.localId.equals(localId)))
        .write(MessagesCompanion(sendStatus: Value(status)));
  }

  /// Обновить контент сообщения (редактирование / обновление payload опроса)
  Future<void> updateMessageContent(
    String serverId,
    String content, [
    String? entities,
    String? mediaPayload,
    bool isEdited = true,
    bool? hasMediaSpoiler,
    String? fileUrl,
    String? fileName,
    String? messageType,
    bool? invertMedia,
  ]) async {
    await ensureInitialized();
    await (update(messages)..where((t) => t.serverId.equals(serverId)))
        .write(MessagesCompanion(
      content: Value(content),
      entities: entities != null ? Value(entities) : const Value.absent(),
      mediaPayload:
          mediaPayload != null ? Value(mediaPayload) : const Value.absent(),
      isEdited: Value(isEdited),
      hasMediaSpoiler: hasMediaSpoiler != null
          ? Value(hasMediaSpoiler)
          : const Value.absent(),
      fileUrl: fileUrl != null ? Value(fileUrl) : const Value.absent(),
      fileName: fileName != null ? Value(fileName) : const Value.absent(),
      messageType:
          messageType != null ? Value(messageType) : const Value.absent(),
      invertMedia:
          invertMedia != null ? Value(invertMedia) : const Value.absent(),
    ));
  }

  /// Обновить таймер автоудаления сообщений в чате
  Future<void> updateChatAutoDeleteTime(String chatId, int ttlSeconds) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(messageAutoDeleteTime: Value(ttlSeconds)),
    );
  }

  /// Обновить сохранённое оформление (тема/обои) чата
  Future<void> updateChatAppearanceJson(
      String chatId, String? appearanceJson) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(appearanceJson: Value(appearanceJson)),
    );
  }

  /// Пометить одноразовое или TTL-сообщение как просмотренное/сгоревшее
  Future<void> markMessageBurned(
    String serverId, {
    String? viewedAt,
    String? expiresAt,
    bool isBurned = true,
  }) async {
    if (serverId.isEmpty) return;
    await ensureInitialized();
    await (update(messages)
          ..where((t) => t.serverId.equals(serverId) | t.localId.equals(serverId)))
        .write(
      MessagesCompanion(
        isBurned: Value(isBurned),
        viewedAt: viewedAt != null ? Value(viewedAt) : const Value.absent(),
        expiresAt: expiresAt != null ? Value(expiresAt) : const Value.absent(),
        fileUrl: isBurned ? const Value('') : const Value.absent(),
      ),
    );
  }

  /// Обновить список тегов сообщения в Избранном
  Future<void> updateMessageSavedTags(
      String serverId, List<String> tags) async {
    if (serverId.isEmpty) return;
    await ensureInitialized();
    final encoded = jsonEncode(tags);
    await (update(messages)
          ..where((t) => t.serverId.equals(serverId) | t.localId.equals(serverId)))
        .write(MessagesCompanion(savedTagsJson: Value(encoded)));
  }

  /// Обновить реакции на сообщении по serverId или localId
  Future<void> updateMessageReactions(
    String messageId,
    Map<String, int> reactions,
    Set<String> myReactions,
  ) async {
    await ensureInitialized();
    final jsonStr = jsonEncode({
      'reactions': reactions,
      'my_reactions': myReactions.toList(),
    });
    await (update(messages)
          ..where((t) => t.serverId.equals(messageId) | t.localId.equals(messageId)))
        .write(MessagesCompanion(
      reactions: Value(jsonStr),
    ));
  }

  /// Обновить счётчик просмотров одного сообщения
  Future<void> updateMessageViews(String messageId, int viewsCount) async {
    if (messageId.isEmpty) return;
    await ensureInitialized();
    await (update(messages)
          ..where((t) =>
              t.serverId.equals(messageId) | t.localId.equals(messageId)))
        .write(MessagesCompanion(viewsCount: Value(viewsCount)));
  }

  /// Пакетно обновить счётчики просмотров сообщений
  Future<void> updateMessagesViews(Map<String, int> viewsByMessageId) async {
    if (viewsByMessageId.isEmpty) return;
    await ensureInitialized();
    await batch((b) {
      viewsByMessageId.forEach((messageId, viewsCount) {
        if (messageId.isEmpty) return;
        b.update(
          messages,
          MessagesCompanion(viewsCount: Value(viewsCount)),
          where: (t) =>
              t.serverId.equals(messageId) | t.localId.equals(messageId),
        );
      });
    });
  }

  /// Пакетно обновить счётчики пересылок сообщений
  Future<void> updateMessagesForwards(
    Map<String, int> forwardsByServerId,
  ) async {
    if (forwardsByServerId.isEmpty) return;
    await ensureInitialized();
    await batch((b) {
      forwardsByServerId.forEach((messageId, forwardsCount) {
        if (messageId.isEmpty) return;
        b.update(
          messages,
          MessagesCompanion(forwardsCount: Value(forwardsCount)),
          where: (t) =>
              t.serverId.equals(messageId) | t.localId.equals(messageId),
        );
      });
    });
  }

  /// Обновить счётчики непрочитанных упоминаний и реакций в чате
  Future<void> updateChatUnreadBadges(
    String chatId, {
    required int unreadMentionsCount,
    required int unreadReactionsCount,
  }) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        unreadMentionsCount:
            Value(unreadMentionsCount < 0 ? 0 : unreadMentionsCount),
        unreadReactionsCount:
            Value(unreadReactionsCount < 0 ? 0 : unreadReactionsCount),
      ),
    );
  }

  /// Обновить количество комментариев и список последних комментаторов поста канала
  Future<void> updatePostCommentsMeta({
    required String messageId,
    int? commentsCount,
    String? recentRepliersJson,
  }) async {
    if (messageId.isEmpty) return;
    await ensureInitialized();
    await (update(messages)
          ..where((t) =>
              t.serverId.equals(messageId) | t.localId.equals(messageId)))
        .write(
      MessagesCompanion(
        commentsCount:
            commentsCount != null ? Value(commentsCount) : const Value.absent(),
        recentRepliersJson: recentRepliersJson != null
            ? Value(recentRepliersJson)
            : const Value.absent(),
      ),
    );
  }

  /// Удалить сообщение по serverId или localId
  Future<void> deleteMessage(String messageId) async {
    await (delete(messages)
          ..where((t) => t.serverId.equals(messageId) | t.localId.equals(messageId)))
        .go();
  }

  /// Пакетно удалить сообщения по списку serverId или localId
  Future<void> deleteMessagesBatch(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await ensureInitialized();
    await (delete(messages)
          ..where((t) =>
              t.serverId.isIn(messageIds) | t.localId.isIn(messageIds)))
        .go();
  }

  /// Получить последнее сообщение основной ленты чата (включая ответы/комментарии в группе обсуждений)
  Future<DbMessage?> getLastMessageForChat(String chatId) async {
    return (select(messages)
          ..where((t) => t.chatId.equals(chatId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Удалить все сообщения чата
  Future<void> deleteMessagesForChat(String chatId) async {
    await (delete(messages)..where((t) => t.chatId.equals(chatId))).go();
  }

  /// Пометить сообщения как прочитанные (отправителя в чате) с сохранением времени прочтения read_at
  Future<void> markMessagesAsRead(
    String chatId,
    String senderId, {
    String? readAt,
  }) async {
    await ensureInitialized();
    final effectiveReadAt = readAt ?? DateTime.now().toUtc().toIso8601String();
    final unreadMsgs = await (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              t.senderId.equals(senderId) &
              t.isRead.equals(false)))
        .get();

    if (unreadMsgs.isEmpty) return;

    await batch((b) {
      for (final msg in unreadMsgs) {
        Map<String, dynamic> mp = {};
        if (msg.mediaPayload != null && msg.mediaPayload!.isNotEmpty) {
          try {
            final decoded = jsonDecode(msg.mediaPayload!);
            if (decoded is Map) {
              mp = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }
        mp['read_at'] ??= effectiveReadAt;
        b.update(
          messages,
          MessagesCompanion(
            isRead: const Value(true),
            mediaPayload: Value(jsonEncode(mp)),
          ),
          where: (t) => t.localId.equals(msg.localId),
        );
      }
    });
  }

  /// Обновить время прочтения (read_at) и/или прослушивания (listened_at) конкретного сообщения
  Future<void> updateMessageReadAndListened(
    String messageId, {
    bool? isRead,
    String? readAt,
    String? listenedAt,
    bool? isListened,
  }) async {
    await ensureInitialized();
    final existing = await (select(messages)
          ..where(
              (t) => t.serverId.equals(messageId) | t.localId.equals(messageId))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) return;

    Map<String, dynamic> mp = {};
    if (existing.mediaPayload != null && existing.mediaPayload!.isNotEmpty) {
      try {
        final decoded = jsonDecode(existing.mediaPayload!);
        if (decoded is Map) {
          mp = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    if (readAt != null && readAt.isNotEmpty) {
      mp['read_at'] ??= readAt;
    }
    if (listenedAt != null && listenedAt.isNotEmpty) {
      mp['listened_at'] ??= listenedAt;
    }
    if (isListened != null) {
      mp['is_listened'] = isListened;
    }

    await (update(messages)..where((t) => t.localId.equals(existing.localId)))
        .write(MessagesCompanion(
      isRead: isRead != null
          ? Value(isRead)
          : (readAt != null ? const Value(true) : const Value.absent()),
      mediaPayload: Value(jsonEncode(mp)),
    ));
  }

  /// Обновить High-Water Mark прочтения чата (lastReadInboxMessageId / lastReadOutboxMessageId)
  Future<void> updateChatReadHwm(
    String chatId, {
    int? lastReadInboxMessageId,
    int? lastReadOutboxMessageId,
    int? unreadCount,
  }) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    final existing = await getChat(chatId);
    if (existing == null) return;

    final nextInbox = lastReadInboxMessageId != null &&
            lastReadInboxMessageId > existing.lastReadInboxMessageId
        ? lastReadInboxMessageId
        : existing.lastReadInboxMessageId;
    final nextOutbox = lastReadOutboxMessageId != null &&
            lastReadOutboxMessageId > existing.lastReadOutboxMessageId
        ? lastReadOutboxMessageId
        : existing.lastReadOutboxMessageId;

    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        lastReadInboxMessageId: Value(nextInbox),
        lastReadOutboxMessageId: Value(nextOutbox),
        unreadCount:
            unreadCount != null ? Value(unreadCount) : const Value.absent(),
      ),
    );
  }

  /// Обновить ID закреплённого сообщения (и список закрепов) в чате
  Future<void> updateChatPinnedMessageId(
    String chatId,
    int? pinnedMessageId, {
    List<int>? pinnedMessageIds,
    bool updatePinnedMessageIds = false,
  }) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        pinnedMessageId: Value(pinnedMessageId),
        pinnedMessageIdsJson: updatePinnedMessageIds
            ? Value(pinnedMessageIds != null
                ? jsonEncode(pinnedMessageIds)
                : null)
            : const Value.absent(),
      ),
    );
  }

  /// Обновить флаг отображения профилей авторов в канале/группе
  Future<void> updateChatShowAuthorProfiles(
    String chatId,
    bool showAuthorProfiles,
  ) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        showAuthorProfiles: Value(showAuthorProfiles),
      ),
    );
  }

  /// Обновить привязанный чат обсуждений (канал <-> группа)
  Future<void> updateChatLinkedChatId(
    String chatId,
    String? linkedChatId,
  ) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        linkedChatId: Value(
          (linkedChatId != null && linkedChatId.isNotEmpty)
              ? linkedChatId
              : null,
        ),
      ),
    );
  }

  /// Обновить статус активного звонка / видеочата в чате
  Future<void> updateChatActiveCall(
    String chatId,
    bool hasActiveCall,
  ) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(hasActiveCall: Value(hasActiveCall)),
    );
  }

  /// Обновить настройки группы/канала в локальной БД
  Future<void> updateChatSettings(
    String chatId, {
    String? name,
    String? avatarUrl,
    bool updateAvatarUrl = false,
    String? username,
    bool updateUsername = false,
    bool? isPublic,
    bool? showAuthorProfiles,
    bool? signMessages,
    String? linkedChatId,
    bool updateLinkedChatId = false,
    String? myRole,
    bool? hasActiveCall,
    String? chatPermissionsJson,
    String? reactionSettingsJson,
    bool? hasProtectedContent,
    String? pinnedMessageIdsJson,
    bool updatePinnedMessageIds = false,
    bool? isForum,
    bool? participantsHidden,
    bool? hasAggressiveAntiSpamEnabled,
    int? maxReactionsPerPost,
  }) async {
    if (chatId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        avatarUrl: updateAvatarUrl ? Value(avatarUrl) : const Value.absent(),
        username: updateUsername ? Value(username) : const Value.absent(),
        isPublic: isPublic != null ? Value(isPublic) : const Value.absent(),
        showAuthorProfiles: showAuthorProfiles != null
            ? Value(showAuthorProfiles)
            : const Value.absent(),
        signMessages:
            signMessages != null ? Value(signMessages) : const Value.absent(),
        linkedChatId: updateLinkedChatId
            ? Value((linkedChatId != null && linkedChatId.isNotEmpty)
                ? linkedChatId
                : null)
            : const Value.absent(),
        myRole: myRole != null ? Value(myRole) : const Value.absent(),
        hasActiveCall: hasActiveCall != null
            ? Value(hasActiveCall)
            : const Value.absent(),
        chatPermissionsJson: chatPermissionsJson != null
            ? Value(chatPermissionsJson)
            : const Value.absent(),
        reactionSettingsJson: reactionSettingsJson != null
            ? Value(reactionSettingsJson)
            : const Value.absent(),
        hasProtectedContent: hasProtectedContent != null
            ? Value(hasProtectedContent)
            : const Value.absent(),
        pinnedMessageIdsJson: updatePinnedMessageIds
            ? Value(pinnedMessageIdsJson)
            : const Value.absent(),
        isForum: isForum != null ? Value(isForum) : const Value.absent(),
        participantsHidden: participantsHidden != null
            ? Value(participantsHidden)
            : const Value.absent(),
        hasAggressiveAntiSpamEnabled: hasAggressiveAntiSpamEnabled != null
            ? Value(hasAggressiveAntiSpamEnabled)
            : const Value.absent(),
        maxReactionsPerPost: maxReactionsPerPost != null
            ? Value(maxReactionsPerPost)
            : const Value.absent(),
      ),
    );
  }

  /// Обновить кэшированную кастомизацию пользователя в личных чатах и сообщениях
  Future<void> updateUserCustomizationJson(
    String userId,
    String? customizationJson,
  ) async {
    if (userId.isEmpty) return;
    await ensureInitialized();
    await (update(chats)
          ..where((t) =>
              t.chatType.equals('private') & t.otherUserId.equals(userId)))
        .write(
      ChatsCompanion(peerCustomizationJson: Value(customizationJson)),
    );
    await (update(messages)..where((t) => t.senderId.equals(userId))).write(
      MessagesCompanion(senderCustomizationJson: Value(customizationJson)),
    );
  }

  /// Пометить исходящие сообщения пользователя в чате прочитанными до maxMessageId (O(1) HWM)
  Future<void> markOutboxMessagesReadUpTo(
    String chatId,
    String myUserId,
    int maxMessageId, {
    String? readAt,
  }) async {
    if (chatId.isEmpty || maxMessageId <= 0) return;
    await ensureInitialized();
    await updateChatReadHwm(
      chatId,
      lastReadOutboxMessageId: maxMessageId,
    );
    final effectiveReadAt = readAt ?? DateTime.now().toUtc().toIso8601String();
    final unreadOutbox = await (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              (myUserId.isNotEmpty ? t.senderId.equals(myUserId) : const Constant(true)) &
              t.isRead.equals(false)))
        .get();
    if (unreadOutbox.isEmpty) return;

    await batch((b) {
      for (final msg in unreadOutbox) {
        final sid = int.tryParse(msg.serverId ?? msg.localId) ?? 0;
        if (sid > 0 && sid <= maxMessageId) {
          Map<String, dynamic> mp = {};
          if (msg.mediaPayload != null && msg.mediaPayload!.isNotEmpty) {
            try {
              final decoded = jsonDecode(msg.mediaPayload!);
              if (decoded is Map) {
                mp = Map<String, dynamic>.from(decoded);
              }
            } catch (_) {}
          }
          mp['read_at'] ??= effectiveReadAt;
          b.update(
            messages,
            MessagesCompanion(
              isRead: const Value(true),
              mediaPayload: Value(jsonEncode(mp)),
            ),
            where: (t) => t.localId.equals(msg.localId),
          );
        }
      }
    });
  }

  // === SYNC STATE ===

  /// Получить последний USN для пользователя
  Future<int> getLastKnownUsn(String userId) async {
    final state = await (select(syncStates)
          ..where((t) => t.userId.equals(userId))
          ..limit(1))
        .getSingleOrNull();
    return state?.lastKnownUsn ?? 0;
  }

  /// Обновить последний USN
  Future<void> setLastKnownUsn(String userId, int usn) async {
    await into(syncStates).insertOnConflictUpdate(
      SyncStatesCompanion(
        userId: Value(userId),
        lastKnownUsn: Value(usn),
        lastSyncAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  // === БАНКОВСКИЕ КАРТЫ ===

  /// Получить все сохраненные карты
  Future<List<DbBankingCard>> getBankingCards() {
    return (select(bankingCards)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }

  /// Сохранить карту
  Future<void> saveBankingCard(BankingCardsCompanion card) async {
    await into(bankingCards).insertOnConflictUpdate(card);
  }

  /// Удалить карту
  Future<void> deleteBankingCard(int id) async {
    await (delete(bankingCards)..where((t) => t.id.equals(id))).go();
  }

  /// Получить чат "Избранное" (saved)
  Future<DbChat?> getSavedChat() async {
    await ensureInitialized();
    final list = await (select(chats)..where((t) => t.chatType.equals('saved'))).get();
    if (list.isEmpty) return null;
    return list.firstWhere(
      (c) => !c.chatId.startsWith('saved_'),
      orElse: () => list.first,
    );
  }

  /// Найти личный чат с конкретным пользователем по otherUserId
  Future<DbChat?> getPrivateChatWithUser(String targetUserId) async {
    if (targetUserId.isEmpty) return null;
    await ensureInitialized();
    final list = await (select(chats)
          ..where((t) => t.chatType.equals('private') & t.otherUserId.equals(targetUserId)))
        .get();
    return list.firstOrNull;
  }

  /// Получить медиафайлы чата (фото и обычные видео, без кружочков)
  Future<List<DbMessage>> getSharedMediaForChat(String chatId, {int limit = 300}) async {
    if (chatId.isEmpty) return [];
    await ensureInitialized();
    return (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              (t.messageType.equals('image') | t.messageType.equals('video')) &
              t.isRound.equals(false) &
              t.fileUrl.isNotNull() &
              t.fileUrl.isNotValue(''))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Получить документы/файлы чата
  Future<List<DbMessage>> getSharedFilesForChat(String chatId, {int limit = 300}) async {
    if (chatId.isEmpty) return [];
    await ensureInitialized();
    return (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              (t.messageType.equals('file') | t.messageType.equals('document')) &
              t.fileUrl.isNotNull() &
              t.fileUrl.isNotValue(''))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Получить голосовые сообщения и видео-кружочки чата
  Future<List<DbMessage>> getSharedVoiceForChat(String chatId, {int limit = 300}) async {
    if (chatId.isEmpty) return [];
    await ensureInitialized();
    return (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              (t.messageType.equals('voice') |
                  t.messageType.equals('round') |
                  t.isRound.equals(true)) &
              t.fileUrl.isNotNull() &
              t.fileUrl.isNotValue(''))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Получить сообщения со ссылками в чате
  Future<List<DbMessage>> getSharedLinksForChat(String chatId, {int limit = 300}) async {
    if (chatId.isEmpty) return [];
    await ensureInitialized();
    return (select(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              (t.content.like('%http://%') |
                  t.content.like('%https://%') |
                  t.content.like('%www.%') |
                  t.entities.like('%"url"%') |
                  t.entities.like('%"text_link"%')))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Получить все сообщения с прикреплёнными файлами (для подсчёта и очистки локального кэша по чатам)
  Future<List<DbMessage>> getMessagesWithFiles({String? chatId}) async {
    await ensureInitialized();
    final stmt = select(messages)
      ..where((t) {
        final hasFile = t.fileUrl.isNotNull() & t.fileUrl.isNotValue('');
        if (chatId != null && chatId.isNotEmpty) {
          return t.chatId.equals(chatId) & hasFile;
        }
        return hasFile;
      });
    return stmt.get();
  }

  /// Локальный мгновенный поиск по чатам (Unicode / регистронезависимый)
  Future<List<DbChat>> searchChatsLocal(String query, {int limit = 20}) async {
    final qLower = query.trim().toLowerCase();
    if (qLower.isEmpty) return [];
    await ensureInitialized();
    final allChats = await getChats();
    final matched = <DbChat>[];
    for (final c in allChats) {
      final nameMatch = c.name.toLowerCase().contains(qLower);
      final usernameMatch =
          c.username != null && c.username!.toLowerCase().contains(qLower);
      if (nameMatch || usernameMatch) {
        matched.add(c);
        if (matched.length >= limit) break;
      }
    }
    return matched;
  }

  /// Локальный мгновенный поиск по сообщениям (с поддержкой регистронезависимого поиска кириллицы/латиницы)
  Future<List<DbMessage>> searchMessagesLocal(
    String query, {
    String? chatId,
    int limit = 30,
  }) async {
    final qLower = query.trim().toLowerCase();
    if (qLower.isEmpty) return [];
    await ensureInitialized();

    final trimmedChatId = chatId?.trim() ?? '';
    final stmt = select(messages)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    if (trimmedChatId.isNotEmpty) {
      stmt
        ..where((t) => t.chatId.equals(trimmedChatId))
        ..limit(2000);
    } else {
      stmt.limit(3000);
    }

    final candidates = await stmt.get();
    final matched = <DbMessage>[];
    for (final m in candidates) {
      final contentMatch = m.content.toLowerCase().contains(qLower);
      final fileMatch =
          m.fileName != null && m.fileName!.toLowerCase().contains(qLower);
      final senderMatch =
          m.senderName != null && m.senderName!.toLowerCase().contains(qLower);
      if (contentMatch || fileMatch || senderMatch) {
        matched.add(m);
        if (matched.length >= limit) break;
      }
    }
    return matched;
  }

  /// Очистить все данные локальной базы (сообщения, чаты, состояние синхронизации, карты)
  Future<void> clearAllData() async {
    await ensureInitialized();
    await transaction(() async {
      await delete(messages).go();
      await delete(chats).go();
      await delete(syncStates).go();
      await delete(bankingCards).go();
    });
    debugPrint('AppDatabase: All local data cleared');
  }
}

