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

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  static QueryExecutor _openConnection(String userId) {
    final dbName = (userId.isNotEmpty && userId != 'default')
        ? 'miptgram_$userId'
        : 'miptgram';
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
        ? 'miptgram_$userId'
        : 'miptgram';
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

  @override
  int get schemaVersion => 9;

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
        },
      );

  /// Инициализация (открыть соединение)
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await customSelect('SELECT 1').getSingle();
      _isInitialized = true;
      debugPrint('AppDatabase: Initialized');
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
  Stream<List<DbChat>> watchChats({int filter = 0}) {
    final query = select(chats);
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
          ..where((t) => t.name.like(pattern) | t.lastMessage.like(pattern))
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
    final query = selectOnly(chats)..addColumns([sumCol]);
    return query.watchSingleOrNull().map((row) => row?.read(sumCol) ?? 0);
  }

  /// Получить все чаты, отсортированные по updatedAt (убывание)
  Future<List<DbChat>> getChats() async {
    await ensureInitialized();
    return (select(chats)
          ..orderBy([
            (t) => OrderingTerm(expression: t.chatType.equals('saved'), mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.isPinned, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// Получить чат по server chatId
  Future<DbChat?> getChat(String chatId) async {
    await ensureInitialized();
    return (select(chats)..where((t) => t.chatId.equals(chatId)))
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
    bool incrementUnread = false,
  }) async {
    await ensureInitialized();
    final existing = await getChat(chatId);
    if (existing == null) return;
    final newUnread =
        incrementUnread ? existing.unreadCount + 1 : existing.unreadCount;
    await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
      ChatsCompanion(
        lastMessage: Value(content),
        lastMessageTime: Value(createdAt),
        lastMessageType: Value(messageType),
        lastMessageIsRound: Value(isRound),
        lastMessageFileUrl: Value(fileUrl),
        lastMessageGroupedId: Value(groupedId),
        updatedAt: Value(createdAt),
        unreadCount: Value(newUnread),
      ),
    );
  }

  /// Пересчитать последнее сообщение чата на основе последней записи в таблице сообщений
  Future<void> refreshChatLastMessageFromDb(String chatId) async {
    await ensureInitialized();
    final lastMsg = await getLastMessageForChat(chatId);
    final existing = await getChat(chatId);
    if (existing == null) return;

    if (lastMsg == null) {
      await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
        const ChatsCompanion(
          lastMessage: Value(null),
          lastMessageTime: Value(null),
          lastMessageType: Value(null),
          lastMessageIsRound: Value(false),
          lastMessageFileUrl: Value(null),
          lastMessageGroupedId: Value(null),
        ),
      );
    } else {
      final isRound = lastMsg.isRound || lastMsg.messageType == 'round';
      await (update(chats)..where((t) => t.chatId.equals(chatId))).write(
        ChatsCompanion(
          lastMessage: Value(lastMsg.content),
          lastMessageTime: Value(lastMsg.createdAt),
          lastMessageType: Value(lastMsg.messageType),
          lastMessageIsRound: Value(isRound),
          lastMessageFileUrl: Value(lastMsg.fileUrl),
          lastMessageGroupedId: Value(lastMsg.groupedId),
          updatedAt: Value(lastMsg.createdAt),
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
    await (update(messages)..where((t) => t.senderId.equals(userId)))
        .write(MessagesCompanion(senderAvatarUrl: Value(avatarUrl)));
  }

  /// Убедиться, что чат "Избранное" существует локально
  Future<void> ensureSavedChatExists(String userId) async {
    await ensureInitialized();
    final existing = await (select(chats)..where((t) => t.chatType.equals('saved'))).getSingleOrNull();
    if (existing == null) {
      await saveChat(ChatsCompanion(
        chatId: Value('saved_$userId'),
        chatType: const Value('saved'),
        name: const Value('Избранное'),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ));
      debugPrint('AppDatabase: Created local "Saved Messages" chat for $userId');
    }
  }

  /// Миграция локального chatId Избранного при получении серверного chatId
  Future<void> migrateSavedChatId(String localSavedId, String serverSavedId) async {
    if (localSavedId == serverSavedId) return;
    await ensureInitialized();
    await customStatement(
      'UPDATE chats SET chat_id = ? WHERE chat_id = ?',
      [serverSavedId, localSavedId],
    );
    await customStatement(
      'UPDATE messages SET chat_id = ? WHERE chat_id = ?',
      [serverSavedId, localSavedId],
    );
  }

  // === СООБЩЕНИЯ ===

  /// Получить сообщения чата с пагинацией
  /// [beforeCreatedAt] — курсор (ISO 8601), загружать сообщения старше этого
  /// [limit] — количество
  Future<List<DbMessage>> getMessages(
    String chatId, {
    String? beforeCreatedAt,
    int limit = 50,
  }) async {
    await ensureInitialized();
    final stmt = select(messages);
    if (beforeCreatedAt != null) {
      stmt.where((t) =>
          t.chatId.equals(chatId) &
          t.createdAt.isSmallerThanValue(beforeCreatedAt));
    } else {
      stmt.where((t) => t.chatId.equals(chatId));
    }
    stmt.orderBy([(t) => OrderingTerm.desc(t.createdAt), (t) => OrderingTerm.desc(t.localId)]);
    stmt.limit(limit);
    return stmt.get();
  }

  /// Получить сообщение по localId
  Future<DbMessage?> getMessageByLocalId(String localId) async {
    await ensureInitialized();
    return (select(messages)..where((t) => t.localId.equals(localId)))
        .getSingleOrNull();
  }

  /// Получить сообщение по serverId
  Future<DbMessage?> getMessageByServerId(String serverId) async {
    await ensureInitialized();
    return (select(messages)..where((t) => t.serverId.equals(serverId)))
        .getSingleOrNull();
  }

  /// Сохранить сообщение (upsert по localId — primary key)
  /// Если у сообщения есть serverId, сначала проверяет существующую запись
  /// по serverId и переиспользует её localId для корректного обновления
  Future<void> saveMessage(MessagesCompanion message) async {
    await ensureInitialized();
    // Если есть serverId (не absent и не null), проверить существующее сообщение
    final serverIdValue = message.serverId;
    final hasServerId = serverIdValue.present && serverIdValue.value != null;
    if (hasServerId) {
      final existing = await getMessageByServerId(serverIdValue.value!);
      if (existing != null) {
        // Переиспользовать существующий localId для корректного upsert
        await into(messages).insertOnConflictUpdate(
          message.copyWith(localId: Value(existing.localId)),
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

  /// Обновить контент сообщения (редактирование)
  Future<void> updateMessageContent(String serverId, String content,
      [String? entities]) async {
    await (update(messages)..where((t) => t.serverId.equals(serverId)))
        .write(MessagesCompanion(
      content: Value(content),
      entities: entities != null ? Value(entities) : const Value.absent(),
      isEdited: const Value(true),
    ));
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

  /// Удалить сообщение по serverId или localId
  Future<void> deleteMessage(String messageId) async {
    await (delete(messages)
          ..where((t) => t.serverId.equals(messageId) | t.localId.equals(messageId)))
        .go();
  }

  /// Получить последнее сообщение чата
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

  /// Пометить сообщения как прочитанные (отправителя в чате)
  Future<void> markMessagesAsRead(String chatId, String senderId) async {
    await (update(messages)
          ..where((t) =>
              t.chatId.equals(chatId) &
              t.senderId.equals(senderId) &
              t.isRead.equals(false)))
        .write(const MessagesCompanion(isRead: Value(true)));
  }

  // === SYNC STATE ===

  /// Получить последний USN для пользователя
  Future<int> getLastKnownUsn(String userId) async {
    final state = await (select(syncStates)
          ..where((t) => t.userId.equals(userId)))
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
