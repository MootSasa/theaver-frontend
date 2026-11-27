import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_channels.dart';
import 'notification_history_store.dart';
import 'notification_images.dart';
import 'notification_payload.dart';

/// Per-notification display options resolved from user settings.
class MessagePresentationOptions {
  const MessagePresentationOptions({
    this.showPreview = true,
    this.soundEnabled = true,
    this.vibrationPattern,
    this.vibrationEnabled = true,
  });

  final bool showPreview;
  final bool soundEnabled;
  final Int64List? vibrationPattern;
  final bool vibrationEnabled;
}

/// Renders chat-message notifications through flutter_local_notifications on
/// Android, iOS and macOS.
///
/// * One notification per chat. On Android it uses `id 0 + tag chat_<id>` — the
///   same key the backend uses for FCM/HMS notification messages — so a
///   foreground notification replaces the background push notification and vice versa.
/// * Android: MessagingStyle with recent history, avatars, "Ответить" (inline
///   reply) and "Прочитано" actions, a group summary.
/// * iOS/macOS: thread per chat, category with reply/read actions.
///
/// Usable from the main isolate and from background isolates.
class MessageNotificationPresenter {
  MessageNotificationPresenter(this.plugin);

  final FlutterLocalNotificationsPlugin plugin;

  static const String groupKey = 'app.theaver.messenger.MESSAGES';
  static const String actionReply = 'reply';
  static const String actionMarkRead = 'mark_read';
  static const String darwinMessageCategory = 'message';
  static const String darwinCallCategory = 'incoming_call';
  static const int _summaryId = 1;
  static const String _summaryTag = 'messages_summary';
  static const Color _accent = Color(0xFF5B7FFF);

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get _isDarwin => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  /// Android tag of a chat notification (shared with the backend).
  static String tagFor(String chatId) => 'chat_$chatId';

  /// Notification ID of a chat. Android uses 0 + tag (matches FCM/HMS); Darwin
  /// has no tags, so a stable per-chat ID is used.
  static int idFor(String chatId) {
    if (_isAndroid) return 0;
    return _stableId('chat_$chatId');
  }

  static int _stableId(String key) {
    // FNV-1a 31-bit: stable across isolates and app restarts (String.hashCode is not guaranteed).
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 || hash == 1 ? hash + 2 : hash;
  }

  /// Darwin notification categories (reply/read for messages, accept/decline for calls).
  static List<DarwinNotificationCategory> darwinCategories() => <DarwinNotificationCategory>[
        DarwinNotificationCategory(
          darwinMessageCategory,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.text(
              actionReply,
              'Ответить',
              buttonTitle: 'Отправить',
              placeholder: 'Сообщение',
            ),
            DarwinNotificationAction.plain(actionMarkRead, 'Прочитано'),
          ],
        ),
        DarwinNotificationCategory(
          darwinCallCategory,
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              'accept_call',
              'Принять',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              'decline_call',
              'Отклонить',
              options: <DarwinNotificationActionOption>{
                DarwinNotificationActionOption.destructive,
              },
            ),
          ],
        ),
      ];

  /// Shows (or updates) the conversation notification for [m].
  Future<void> present(
    ChatMessageNotification m, {
    MessagePresentationOptions options = const MessagePresentationOptions(),
  }) async {
    final text = options.showPreview ? m.text : 'Новое сообщение';
    final history = await NotificationHistoryStore.append(
      m.chatId,
      NotificationHistoryEntry(
        text: text,
        senderName: m.isGroup ? (options.showPreview ? m.senderName : '') : m.chatName,
        senderKey: m.senderId.isNotEmpty ? m.senderId : m.senderName,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        messageId: m.messageId,
      ),
    );

    try {
      await _show(m, history, options);
    } catch (e, st) {
      debugPrint('MessageNotificationPresenter: rich notification failed: $e\n$st');
      // Fallback: plain notification without images/styles so the user still gets it.
      try {
        await _showPlain(m, text, options);
      } catch (e2) {
        debugPrint('MessageNotificationPresenter: plain notification failed: $e2');
      }
    }
  }

  /// Re-renders a chat notification from stored history after an own reply
  /// (inline reply from the notification shade).
  Future<void> appendOwnReply({
    required Map<String, dynamic> tapPayload,
    required String text,
  }) async {
    final m = ChatMessageNotification.fromPush(tapPayload);
    if (m == null) return;
    final history = await NotificationHistoryStore.append(
      m.chatId,
      NotificationHistoryEntry(
        text: text,
        senderName: 'Вы',
        senderKey: 'me',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isOwn: true,
      ),
    );
    try {
      await _show(m, history, const MessagePresentationOptions(), silentUpdate: true);
    } catch (e) {
      debugPrint('MessageNotificationPresenter: reply update failed: $e');
    }
  }

  Future<void> _show(
    ChatMessageNotification m,
    List<NotificationHistoryEntry> history,
    MessagePresentationOptions options, {
    bool silentUpdate = false,
  }) async {
    final payload = jsonEncode(m.toTapPayload());
    final last = history.isNotEmpty ? history.last.text : m.text;
    final title = m.chatName.isNotEmpty ? m.chatName : 'Theaver';
    final body = (m.isGroup && history.isNotEmpty && history.last.senderName.isNotEmpty && !history.last.isOwn)
        ? '${history.last.senderName}: $last'
        : last;

    AndroidNotificationDetails? android;
    if (_isAndroid) {
      android = await _androidDetails(m, history, options, silentUpdate: silentUpdate);
    }
    DarwinNotificationDetails? darwin;
    if (_isDarwin) {
      darwin = DarwinNotificationDetails(
        presentAlert: !silentUpdate,
        presentBanner: !silentUpdate,
        presentList: true,
        presentBadge: true,
        presentSound: options.soundEnabled && !silentUpdate,
        threadIdentifier: tagFor(m.chatId),
        categoryIdentifier: darwinMessageCategory,
        subtitle: null,
      );
    }

    await plugin.show(
      idFor(m.chatId),
      title,
      body,
      NotificationDetails(android: android, iOS: darwin, macOS: darwin),
      payload: payload,
    );

    if (_isAndroid) {
      await _updateAndroidSummary();
    }
  }

  Future<AndroidNotificationDetails> _androidDetails(
    ChatMessageNotification m,
    List<NotificationHistoryEntry> history,
    MessagePresentationOptions options, {
    bool silentUpdate = false,
  }) async {
    final customChannel = await NotificationChannels.customChannelFor(m.chatId);
    final channelId = customChannel ??
        NotificationChannels.forChat(
          isGroup: m.isGroup,
          isChannel: m.isChannel,
          isMention: m.isMention,
          soundEnabled: options.soundEnabled,
        );

    final chatAvatarPath = await downloadOrGetCachedAvatar(m.avatarUrl);
    final senderAvatarPath = m.isGroup
        ? await downloadOrGetCachedAvatar(m.senderAvatarUrl)
        : chatAvatarPath;

    const me = Person(name: 'Вы', key: 'me');
    final people = <String, Person>{};
    Person personFor(NotificationHistoryEntry e) {
      if (e.isOwn) return me;
      final key = e.senderKey.isNotEmpty ? e.senderKey : e.senderName;
      return people.putIfAbsent(key, () {
        final isLatestSender = key == (m.senderId.isNotEmpty ? m.senderId : m.senderName);
        final iconPath = isLatestSender ? senderAvatarPath : null;
        return Person(
          name: e.senderName.isNotEmpty ? e.senderName : m.chatName,
          key: key,
          icon: iconPath != null ? BitmapFilePathAndroidIcon(iconPath) : null,
        );
      });
    }

    final messages = history
        .map((e) => Message(e.text, DateTime.fromMillisecondsSinceEpoch(e.timestampMs), personFor(e)))
        .toList();

    final style = MessagingStyleInformation(
      me,
      conversationTitle: (m.isGroup || m.isChannel) ? m.chatName : null,
      groupConversation: m.isGroup || m.isChannel,
      messages: messages,
    );

    return AndroidNotificationDetails(
      channelId,
      customChannel != null ? m.chatName : NotificationChannels.label(channelId),
      channelDescription: NotificationChannels.description(channelId),
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      color: _accent,
      largeIcon: (m.isGroup || m.isChannel) && chatAvatarPath != null
          ? FilePathAndroidBitmap(chatAvatarPath)
          : null,
      category: AndroidNotificationCategory.message,
      styleInformation: style,
      groupKey: groupKey,
      tag: tagFor(m.chatId),
      autoCancel: true,
      onlyAlertOnce: silentUpdate,
      playSound: options.soundEnabled,
      enableVibration: options.vibrationEnabled,
      vibrationPattern: options.vibrationPattern,
      when: DateTime.now().millisecondsSinceEpoch,
      showWhen: true,
      visibility: NotificationVisibility.private,
      actions: m.isChannel
          ? const <AndroidNotificationAction>[
              AndroidNotificationAction(actionMarkRead, 'Прочитано', cancelNotification: true),
            ]
          : const <AndroidNotificationAction>[
              AndroidNotificationAction(
                actionReply,
                'Ответить',
                inputs: <AndroidNotificationActionInput>[
                  AndroidNotificationActionInput(label: 'Сообщение'),
                ],
                cancelNotification: false,
                allowGeneratedReplies: true,
              ),
              AndroidNotificationAction(actionMarkRead, 'Прочитано', cancelNotification: true),
            ],
    );
  }

  Future<void> _showPlain(
    ChatMessageNotification m,
    String text,
    MessagePresentationOptions options,
  ) async {
    final channelId = NotificationChannels.forChat(
      isGroup: m.isGroup,
      isChannel: m.isChannel,
      soundEnabled: options.soundEnabled,
    );
    final body = m.isGroup && m.senderName.isNotEmpty ? '${m.senderName}: $text' : text;
    await plugin.show(
      idFor(m.chatId),
      m.chatName.isNotEmpty ? m.chatName : 'Theaver',
      body,
      NotificationDetails(
        android: _isAndroid
            ? AndroidNotificationDetails(
                channelId,
                NotificationChannels.label(channelId),
                channelDescription: NotificationChannels.description(channelId),
                importance: Importance.high,
                priority: Priority.high,
                icon: '@drawable/ic_notification',
                color: _accent,
                tag: tagFor(m.chatId),
                groupKey: groupKey,
              )
            : null,
        iOS: _isDarwin ? DarwinNotificationDetails(threadIdentifier: tagFor(m.chatId)) : null,
        macOS: _isDarwin ? DarwinNotificationDetails(threadIdentifier: tagFor(m.chatId)) : null,
      ),
      payload: jsonEncode(m.toTapPayload()),
    );
  }

  Future<void> _updateAndroidSummary() async {
    final chats = await NotificationHistoryStore.activeChats();
    if (chats.length < 2) {
      try {
        await plugin.cancel(_summaryId, tag: _summaryTag);
      } catch (_) {}
      return;
    }
    final lines = <String>[];
    for (final chatId in chats.reversed.take(6)) {
      final h = await NotificationHistoryStore.read(chatId);
      if (h.isEmpty) continue;
      final e = h.last;
      lines.add(e.senderName.isNotEmpty ? '${e.senderName}: ${e.text}' : e.text);
    }
    final summary = 'Новые сообщения в ${chats.length} чатах';
    await plugin.show(
      _summaryId,
      'Theaver',
      summary,
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.privateChats,
          NotificationChannels.label(NotificationChannels.privateChats),
          channelDescription: NotificationChannels.description(NotificationChannels.privateChats),
          icon: '@drawable/ic_notification',
          color: _accent,
          groupKey: groupKey,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          tag: _summaryTag,
          styleInformation: InboxStyleInformation(lines, summaryText: summary),
        ),
      ),
    );
  }

  /// Removes the chat notification (any source: local, FCM-rendered) and its history.
  Future<void> cancelChat(String chatId) async {
    await NotificationHistoryStore.clear(chatId);
    try {
      if (_isAndroid) {
        await plugin.cancel(0, tag: tagFor(chatId));
        await _updateAndroidSummary();
      } else {
        await plugin.cancel(idFor(chatId));
      }
    } catch (e) {
      debugPrint('MessageNotificationPresenter: cancel failed: $e');
    }
  }

  Future<void> cancelAll() async {
    await NotificationHistoryStore.clearAll();
    try {
      await plugin.cancelAll();
    } catch (_) {}
  }
}
