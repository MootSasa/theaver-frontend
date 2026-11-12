import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android notification channel registry.
///
/// Channel IDs must match the backend (`backend/services/notification/payload.go`),
/// because FCM/HMS notification messages reference them via `channel_id`.
/// Base channel IDs are intentionally unchanged from previous releases so users
/// keep their per-channel system settings.
class NotificationChannels {
  NotificationChannels._();

  static const String privateChats = 'private_chats';
  static const String groupChats = 'group_chats';
  static const String channels = 'channels';
  static const String mentions = 'mentions';
  static const String silent = 'messages_silent';
  static const String incomingCalls = 'incoming_calls_v2';
  static const String missedCalls = 'missed_calls';
  static const String appUpdates = 'app_updates';

  /// Channel group for chats with individual sound/vibration settings.
  static const String customChatsGroup = 'custom_chats';

  /// Legacy channels that are no longer used.
  static const List<String> _legacyChannels = <String>['silent', 'calls'];

  static const Map<String, String> _labels = <String, String>{
    privateChats: 'Личные чаты',
    groupChats: 'Групповые чаты',
    channels: 'Каналы',
    mentions: 'Упоминания',
    silent: 'Беззвучные сообщения',
    incomingCalls: 'Входящие звонки',
    missedCalls: 'Пропущенные звонки',
    appUpdates: 'Обновления приложения',
  };

  static const Map<String, String> _descriptions = <String, String>{
    privateChats: 'Новые сообщения в личных чатах',
    groupChats: 'Новые сообщения в группах',
    channels: 'Новые посты в каналах',
    mentions: 'Упоминания и ответы на ваши сообщения',
    silent: 'Сообщения из чатов, где отключён звук',
    incomingCalls: 'Полноэкранные уведомления о входящих звонках',
    missedCalls: 'Пропущенные звонки',
    appUpdates: 'Выход новых версий Theaver',
  };

  static String label(String id) => _labels[id] ?? 'Уведомления';
  static String description(String id) =>
      _descriptions[id] ?? 'Уведомления Theaver';

  /// Base channel for a chat without individual settings.
  static String forChat({
    required bool isGroup,
    bool isChannel = false,
    bool isMention = false,
    bool soundEnabled = true,
  }) {
    if (!soundEnabled) return silent;
    if (isMention) return mentions;
    if (isChannel) return channels;
    if (isGroup) return groupChats;
    return privateChats;
  }

  static const List<AndroidNotificationChannel> _baseChannels =
      <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      privateChats,
      'Личные чаты',
      description: 'Новые сообщения в личных чатах',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      groupChats,
      'Групповые чаты',
      description: 'Новые сообщения в группах',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      channels,
      'Каналы',
      description: 'Новые посты в каналах',
      importance: Importance.defaultImportance,
    ),
    AndroidNotificationChannel(
      mentions,
      'Упоминания',
      description: 'Упоминания и ответы на ваши сообщения',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      silent,
      'Беззвучные сообщения',
      description: 'Сообщения из чатов, где отключён звук',
      importance: Importance.high,
      playSound: false,
      enableVibration: false,
    ),
    AndroidNotificationChannel(
      incomingCalls,
      'Входящие звонки',
      description: 'Полноэкранные уведомления о входящих звонках',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ),
    AndroidNotificationChannel(
      missedCalls,
      'Пропущенные звонки',
      description: 'Пропущенные звонки',
      importance: Importance.defaultImportance,
      playSound: false,
    ),
    AndroidNotificationChannel(
      appUpdates,
      'Обновления приложения',
      description: 'Выход новых версий Theaver',
      importance: Importance.defaultImportance,
    ),
  ];

  /// Creates all base channels. Safe to call from any isolate and repeatedly:
  /// Android ignores re-creation of an existing channel (importance is immutable).
  static Future<void> ensureBaseChannels(
      FlutterLocalNotificationsPlugin plugin) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final channel in _baseChannels) {
      try {
        await android.createNotificationChannel(channel);
      } catch (e) {
        debugPrint('NotificationChannels: create ${channel.id} failed: $e');
      }
    }
    for (final legacy in _legacyChannels) {
      try {
        await android.deleteNotificationChannel(legacy);
      } catch (_) {}
    }
  }

  // ======================= Per-chat channels =======================

  static const String _prefsVersionPrefix = 'notif_chat_channel_v_';
  static const String _prefsSoundPrefix = 'notif_chat_channel_sound_';
  static const String _prefsVibrationPrefix = 'notif_chat_channel_vibration_';

  /// ID of a per-chat channel for a given version.
  static String chatChannelId(String chatId, int version) =>
      'chat_${chatId}_v$version';

  /// Returns the per-chat channel ID for [chatId] if one exists on this device.
  static Future<String?> customChannelFor(String chatId) async {
    if (kIsWeb || !Platform.isAndroid || chatId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final version = prefs.getInt('$_prefsVersionPrefix$chatId');
      if (version == null) return null;
      return chatChannelId(chatId, version);
    } catch (_) {
      return null;
    }
  }

  /// Stored device-local sound URI of a per-chat channel ('' = silent, null = default).
  static Future<String?> customSoundFor(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('$_prefsSoundPrefix$chatId')) return null;
      return prefs.getString('$_prefsSoundPrefix$chatId');
    } catch (_) {
      return null;
    }
  }

  /// Creates (or re-creates with a bumped version) a per-chat channel.
  ///
  /// Android channel sound/vibration are immutable after creation, so any change
  /// deletes the previous channel and creates `chat_<id>_v<n+1>`.
  /// [soundUri]: null = system default sound, '' = no sound, otherwise a content URI
  /// returned by the system ringtone picker.
  /// Returns the new channel ID, or null when not supported.
  static Future<String?> upsertChatChannel(
    FlutterLocalNotificationsPlugin plugin, {
    required String chatId,
    required String chatTitle,
    required bool isGroup,
    String? soundUri,
    Int64List? vibrationPattern,
    bool vibrationEnabled = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid || chatId.isEmpty) return null;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return null;

    final prefs = await SharedPreferences.getInstance();
    final oldVersion = prefs.getInt('$_prefsVersionPrefix$chatId');
    final newVersion = (oldVersion ?? 0) + 1;
    final newId = chatChannelId(chatId, newVersion);

    try {
      await android.createNotificationChannelGroup(
        const AndroidNotificationChannelGroup(
          customChatsGroup,
          'Особые настройки чатов',
          description: 'Чаты с индивидуальным звуком и вибрацией',
        ),
      );
    } catch (_) {}

    final silentSound = soundUri != null && soundUri.isEmpty;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        newId,
        chatTitle.isNotEmpty ? chatTitle : 'Чат $chatId',
        description: isGroup ? 'Сообщения группы' : 'Сообщения чата',
        groupId: customChatsGroup,
        importance: Importance.high,
        playSound: !silentSound,
        sound: (soundUri != null && soundUri.isNotEmpty)
            ? UriAndroidNotificationSound(soundUri)
            : null,
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled ? vibrationPattern : null,
      ),
    );

    if (oldVersion != null) {
      try {
        await android
            .deleteNotificationChannel(chatChannelId(chatId, oldVersion));
      } catch (_) {}
    }

    await prefs.setInt('$_prefsVersionPrefix$chatId', newVersion);
    if (soundUri == null) {
      await prefs.remove('$_prefsSoundPrefix$chatId');
    } else {
      await prefs.setString('$_prefsSoundPrefix$chatId', soundUri);
    }
    await prefs.setBool('$_prefsVibrationPrefix$chatId', vibrationEnabled);
    return newId;
  }

  /// Removes the per-chat channel; the chat falls back to its base channel.
  static Future<void> removeChatChannel(
      FlutterLocalNotificationsPlugin plugin, String chatId) async {
    if (kIsWeb || !Platform.isAndroid || chatId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getInt('$_prefsVersionPrefix$chatId');
    if (version != null) {
      try {
        await plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.deleteNotificationChannel(chatChannelId(chatId, version));
      } catch (_) {}
    }
    await prefs.remove('$_prefsVersionPrefix$chatId');
    await prefs.remove('$_prefsSoundPrefix$chatId');
    await prefs.remove('$_prefsVibrationPrefix$chatId');
  }
}
