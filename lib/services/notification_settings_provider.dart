import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';
import 'notification_service.dart';
import 'auth_service.dart';
import 'websocket_service.dart';
import '../config/app_config.dart';

/// Provider для управления настройками уведомлений.
/// Синхронизирует глобальные и per-chat настройки с SettingsService и REST API.
class NotificationSettingsProvider extends ChangeNotifier {
  final SettingsService _settingsService = SettingsService();
  final Dio _dio = Dio();

  GlobalNotificationSettings _globalSettings = GlobalNotificationSettings.defaults();
  Map<String, ChatNotificationSettings> _chatSettings = {};
  List<ChatNotificationException> _exceptions = [];
  bool _backgroundConnection = false;

  GlobalNotificationSettings get globalSettings => _globalSettings;
  Map<String, ChatNotificationSettings> get chatSettings => _chatSettings;
  List<ChatNotificationException> get exceptions => _exceptions;
  bool get backgroundConnection => _backgroundConnection;

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Authorization': 'Bearer ${token ?? ""}',
      'Content-Type': 'application/json',
    };
  }

  /// Инициализация: загрузка из SettingsService, запуск NotificationService и синк с сервером
  Future<void> init() async {
    _globalSettings = _settingsService.notificationSettings;
    _chatSettings = _settingsService.allChatNotificationSettings;

    try {
      final prefs = await SharedPreferences.getInstance();
      _backgroundConnection = prefs.getBool('bg_connection_enabled') ?? false;
      await WebSocketService().initKeepAlive();
    } catch (_) {}

    notifyListeners();

    try {
      await NotificationService().init(this);
    } catch (e) {
      debugPrint('NotificationSettingsProvider: NotificationService init error: $e');
    }

    // Фоновая синхронизация с сервером
    loadSettingsFromServer();
    loadExceptionsFromServer();
  }

  /// Включить / выключить постоянное фоновое соединение (Keep-Alive для VPN)
  Future<void> updateBackgroundConnection(bool enabled) async {
    _backgroundConnection = enabled;
    notifyListeners();
    await WebSocketService().setKeepAliveEnabled(enabled);
  }

  /// Загрузить настройки уведомлений с сервера
  Future<void> loadSettingsFromServer() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return;

      final res = await _dio.get(
        '${AppConfig.baseUrl}/api/settings/notifications',
        options: Options(headers: await _authHeaders()),
      );

      if (res.statusCode == 200 && res.data != null) {
        final serverSettings = GlobalNotificationSettings.fromJson(res.data);
        _globalSettings = serverSettings;
        await _settingsService.saveNotificationSettings(serverSettings);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: loadSettingsFromServer error: $e');
    }
  }

  /// Загрузить список исключений чатов с сервера
  Future<void> loadExceptionsFromServer() async {
    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return;

      final res = await _dio.get(
        '${AppConfig.baseUrl}/api/settings/notifications/exceptions',
        options: Options(headers: await _authHeaders()),
      );

      if (res.statusCode == 200 && res.data is List) {
        final list = (res.data as List)
            .map((e) => ChatNotificationException.fromJson(e as Map<String, dynamic>))
            .toList();
        _exceptions = list;

        for (final ex in list) {
          _chatSettings[ex.settings.chatId] = ex.settings;
          await _settingsService.saveChatNotificationSettings(ex.settings.chatId, ex.settings);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: loadExceptionsFromServer error: $e');
    }
  }

  // ============ Глобальные настройки ============

  /// Сохранить глобальные настройки уведомлений
  Future<void> saveGlobalSettings(GlobalNotificationSettings settings) async {
    _globalSettings = settings;
    await _settingsService.saveNotificationSettings(settings);
    notifyListeners();

    try {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        await _dio.put(
          '${AppConfig.baseUrl}/api/settings/notifications',
          data: settings.toServerJson(),
          options: Options(headers: await _authHeaders()),
        );
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: saveGlobalSettings remote error: $e');
    }
  }

  /// Обновить отдельные поля глобальных настроек
  Future<void> updateGlobalSettings({
    bool? notificationsEnabled,
    bool? privateChatNotifications,
    bool? privateChatPreview,
    bool? privateChatSound,
    String? privateChatSoundUri,
    VibrationPattern? privateChatVibration,
    bool? groupChatNotifications,
    bool? groupChatPreview,
    bool? groupChatSound,
    String? groupChatSoundUri,
    VibrationPattern? groupChatVibration,
    bool? channelNotifications,
    bool? channelPreview,
    bool? channelSound,
    String? channelSoundUri,
    VibrationPattern? channelVibration,
    bool? callNotifications,
    bool? callSound,
    bool? callVibration,
    String? callRingtone,
    bool? mentionsNotifications,
    bool? keywordsNotifications,
    bool? badgeEnabled,
    BadgeMode? badgeMode,
    bool? popupEnabled,
    bool? contentPreview,
    bool? includeMutedChats,
    bool? accountNotifications,
    bool? inAppSounds,
    bool? inAppVibrate,
    bool? inAppPreview,
    bool? inAppChatSounds,
    int? repeatNotifications,
  }) async {
    final updated = _globalSettings.copyWith(
      notificationsEnabled: notificationsEnabled,
      privateChatNotifications: privateChatNotifications,
      privateChatPreview: privateChatPreview,
      privateChatSound: privateChatSound,
      privateChatSoundUri: privateChatSoundUri,
      privateChatVibration: privateChatVibration,
      groupChatNotifications: groupChatNotifications,
      groupChatPreview: groupChatPreview,
      groupChatSound: groupChatSound,
      groupChatSoundUri: groupChatSoundUri,
      groupChatVibration: groupChatVibration,
      channelNotifications: channelNotifications,
      channelPreview: channelPreview,
      channelSound: channelSound,
      channelSoundUri: channelSoundUri,
      channelVibration: channelVibration,
      callNotifications: callNotifications,
      callSound: callSound,
      callVibration: callVibration,
      callRingtone: callRingtone,
      mentionsNotifications: mentionsNotifications,
      keywordsNotifications: keywordsNotifications,
      badgeEnabled: badgeEnabled,
      badgeMode: badgeMode,
      popupEnabled: popupEnabled,
      contentPreview: contentPreview,
      includeMutedChats: includeMutedChats,
      accountNotifications: accountNotifications,
      inAppSounds: inAppSounds,
      inAppVibrate: inAppVibrate,
      inAppPreview: inAppPreview,
      inAppChatSounds: inAppChatSounds,
      repeatNotifications: repeatNotifications,
    );
    await saveGlobalSettings(updated);
  }

  // ============ Per-chat настройки ============

  /// Получить per-chat настройки
  ChatNotificationSettings? getChatSettings(String chatId) {
    return _chatSettings[chatId];
  }

  /// Получить эффективные настройки для чата (per-chat или глобальные)
  EffectiveChatSettings getEffectiveSettings(String chatId) {
    return _settingsService.getEffectiveChatSettings(chatId);
  }

  /// Сохранить per-chat настройки
  Future<void> saveChatSettings(String chatId, ChatNotificationSettings settings) async {
    _chatSettings[chatId] = settings;
    await _settingsService.saveChatNotificationSettings(chatId, settings);
    notifyListeners();

    try {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        await _dio.put(
          '${AppConfig.baseUrl}/api/settings/notifications/chats/$chatId',
          data: settings.toServerJson(),
          options: Options(headers: await _authHeaders()),
        );
        loadExceptionsFromServer();
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: saveChatSettings remote error: $e');
    }
  }

  /// Установить mute для чата
  Future<void> setMuteState(String chatId, MuteState state, {DateTime? until}) async {
    final existing = _chatSettings[chatId];
    final updated = (existing ?? ChatNotificationSettings(chatId: chatId)).copyWith(
      muteState: state,
      muteUntil: until,
    );
    await saveChatSettings(chatId, updated);
  }

  /// Установить mentions-only для чата
  Future<void> setMentionsOnly(String chatId, bool mentionsOnly) async {
    final existing = _chatSettings[chatId];
    final updated = (existing ?? ChatNotificationSettings(chatId: chatId)).copyWith(
      mentionsOnly: mentionsOnly,
    );
    await saveChatSettings(chatId, updated);
  }

  /// Установить ключевые слова для чата
  Future<void> setKeywords(String chatId, List<String> keywords) async {
    final existing = _chatSettings[chatId];
    final updated = (existing ?? ChatNotificationSettings(chatId: chatId)).copyWith(
      keywords: keywords,
    );
    await saveChatSettings(chatId, updated);
  }

  /// Удалить per-chat настройки (вернуть к глобальным)
  Future<void> removeChatSettings(String chatId) async {
    _chatSettings.remove(chatId);
    _exceptions.removeWhere((ex) => ex.settings.chatId == chatId);
    await _settingsService.removeChatNotificationSettings(chatId);
    notifyListeners();

    try {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        await _dio.delete(
          '${AppConfig.baseUrl}/api/settings/notifications/chats/$chatId',
          options: Options(headers: await _authHeaders()),
        );
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: removeChatSettings remote error: $e');
    }
  }

  /// Сбросить все настройки уведомлений к дефолтным (глобальные и per-chat)
  Future<void> resetAllSettings() async {
    _globalSettings = GlobalNotificationSettings.defaults();
    _chatSettings = {};
    _exceptions = [];

    await _settingsService.saveNotificationSettings(_globalSettings);
    await _settingsService.resetAllChatNotificationSettings();
    notifyListeners();

    try {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        await _dio.post(
          '${AppConfig.baseUrl}/api/settings/notifications/reset',
          options: Options(headers: await _authHeaders()),
        );
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: resetAllSettings remote error: $e');
    }
  }

  /// Сбросить все per-chat настройки
  Future<void> resetAllChatSettings() async {
    _chatSettings = {};
    _exceptions = [];
    await _settingsService.resetAllChatNotificationSettings();
    notifyListeners();

    try {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        await _dio.post(
          '${AppConfig.baseUrl}/api/settings/notifications/reset',
          options: Options(headers: await _authHeaders()),
        );
        await _dio.put(
          '${AppConfig.baseUrl}/api/settings/notifications',
          data: _globalSettings.toServerJson(),
          options: Options(headers: await _authHeaders()),
        );
      }
    } catch (e) {
      debugPrint('NotificationSettingsProvider: resetAllChatSettings remote error: $e');
    }
  }

  /// Проверить, нужно ли показывать уведомление для чата
  bool shouldShowNotification(String chatId, {bool isMention = false}) {
    if (!_globalSettings.notificationsEnabled) return false;

    final effective = getEffectiveSettings(chatId);

    if (effective.isMuted) return false;
    if (effective.mentionsOnly && !isMention) return false;

    return true;
  }
}
