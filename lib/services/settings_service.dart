import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'glass_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для хранения и управления настройками пользователя
class SettingsService {
  SettingsService._internal();
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;

  late SharedPreferences _prefs;

  // Ключи для хранения настроек
  static const String _profileKey = 'user_profile';
  static const String _foldersKey = 'chat_folders';
  static const String _storageSettingsKey = 'storage_settings';
  static const String _powerSavingKey = 'power_saving_settings';
  static const String _liquidGlassDesignKey = 'liquid_glass_design';
  static const String _glassModeKey = 'glass_mode';
  static const String _manualLightAngleKey = 'manual_light_angle';
  static const String _glassBlurKey = 'glass_blur';
  static const String _notificationSettingsKey = 'notification_settings';
  static const String _chatNotificationSettingsKey = 'chat_notification_settings';

  // Кэшированные данные
  UserProfile? _cachedProfile;
  List<String>? _cachedFolders;
  StorageSettings? _cachedStorageSettings;
  PowerSavingSettings? _cachedPowerSavingSettings;
  bool? _cachedLiquidGlassDesign;
  GlassMode? _cachedGlassMode;
  double? _cachedManualLightAngle;
  double? _cachedGlassBlur;
  GlobalNotificationSettings? _cachedNotificationSettings;
  Map<String, ChatNotificationSettings>? _cachedChatNotificationSettings;

  /// Инициализация сервиса
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
  }

  Future<void> _loadSettings() async {
    // Загрузка профиля
    final profileJson = _prefs.getString(_profileKey);
    if (profileJson != null) {
      _cachedProfile = UserProfile.fromJson(jsonDecode(profileJson));
    }

    // Загрузка папок
    final foldersJson = _prefs.getString(_foldersKey);
    if (foldersJson != null) {
      _cachedFolders = List<String>.from(jsonDecode(foldersJson));
    } else {
      _cachedFolders = ['Work', 'Family', 'Friends', 'Acquaintances'];
    }

    // Загрузка настроек хранилища
    final storageJson = _prefs.getString(_storageSettingsKey);
    if (storageJson != null) {
      _cachedStorageSettings = StorageSettings.fromJson(jsonDecode(storageJson));
    } else {
      _cachedStorageSettings = StorageSettings.defaults();
    }

    // Загрузка настроек энергосбережения
    final powerSavingJson = _prefs.getString(_powerSavingKey);
    if (powerSavingJson != null) {
      _cachedPowerSavingSettings = PowerSavingSettings.fromJson(jsonDecode(powerSavingJson));
    } else {
      _cachedPowerSavingSettings = PowerSavingSettings.defaults();
    }

    // Загрузка настройки Liquid Glass дизайна
    _cachedLiquidGlassDesign = _prefs.getBool(_liquidGlassDesignKey) ?? false;

    // Загрузка режима стекла (новый формат)
    final glassModeIndex = _prefs.getInt(_glassModeKey);
    if (glassModeIndex != null && glassModeIndex >= 0 && glassModeIndex < GlassMode.values.length) {
      _cachedGlassMode = GlassMode.values[glassModeIndex];
    } else if (_cachedLiquidGlassDesign == true) {
      // Миграция со старого формата: если был включён — ставим full
      _cachedGlassMode = GlassMode.full;
    } else {
      _cachedGlassMode = GlassMode.disabled;
    }

    _cachedManualLightAngle = _prefs.getDouble(_manualLightAngleKey) ?? 62.0;
    _cachedGlassBlur = _prefs.getDouble(_glassBlurKey) ?? 8.0;

    // Загрузка глобальных настроек уведомлений
    final notifJson = _prefs.getString(_notificationSettingsKey);
    if (notifJson != null) {
      _cachedNotificationSettings = GlobalNotificationSettings.fromJson(jsonDecode(notifJson));
    } else {
      _cachedNotificationSettings = GlobalNotificationSettings.defaults();
    }

    // Загрузка per-chat настроек уведомлений
    final chatNotifJson = _prefs.getString(_chatNotificationSettingsKey);
    if (chatNotifJson != null) {
      final Map<String, dynamic> decoded = jsonDecode(chatNotifJson);
      _cachedChatNotificationSettings = decoded.map(
        (key, value) => MapEntry(key, ChatNotificationSettings.fromJson(value as Map<String, dynamic>)),
      );
    } else {
      _cachedChatNotificationSettings = {};
    }
  }

  // ============ Профиль ============

  /// Получить профиль пользователя
  UserProfile? get userProfile => _cachedProfile;

  /// Сохранить профиль пользователя
  Future<void> saveUserProfile(UserProfile profile) async {
    _cachedProfile = profile;
    await _prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  /// Обновить профиль с сервера
  Future<void> updateProfileFromServer(Map<String, dynamic> userData) async {
    final profile = UserProfile.fromJson(userData);
    await saveUserProfile(profile);
  }

  // ============ Папки чатов ============

  /// Получить список папок
  List<String> get folders => _cachedFolders ?? [];

  /// Сохранить список папок
  Future<void> saveFolders(List<String> folders) async {
    _cachedFolders = folders;
    await _prefs.setString(_foldersKey, jsonEncode(folders));
  }

  /// Добавить папку
  Future<void> addFolder(String folderName) async {
    _cachedFolders ??= [];
    if (!_cachedFolders!.contains(folderName)) {
      _cachedFolders!.add(folderName);
      await _prefs.setString(_foldersKey, jsonEncode(_cachedFolders));
    }
  }

  /// Переименовать папку
  Future<void> renameFolder(String oldName, String newName) async {
    if (_cachedFolders == null) return;
    final index = _cachedFolders!.indexOf(oldName);
    if (index != -1) {
      _cachedFolders![index] = newName;
      await _prefs.setString(_foldersKey, jsonEncode(_cachedFolders));
    }
  }

  /// Удалить папку
  Future<void> removeFolder(String folderName) async {
    if (_cachedFolders == null) return;
    _cachedFolders!.remove(folderName);
    await _prefs.setString(_foldersKey, jsonEncode(_cachedFolders));
  }

  // ============ Настройки хранилища ============

  /// Получить настройки хранилища
  StorageSettings get storageSettings => _cachedStorageSettings ?? StorageSettings.defaults();

  /// Сохранить настройки хранилища
  Future<void> saveStorageSettings(StorageSettings settings) async {
    _cachedStorageSettings = settings;
    await _prefs.setString(_storageSettingsKey, jsonEncode(settings.toJson()));
  }

  /// Обновить отдельные настройки автозагрузки
  Future<void> updateAutoDownloadSettings({
    bool? photosWifi,
    bool? videosWifi,
    bool? filesWifi,
    bool? audioWifi,
    bool? photosCellular,
    bool? videosCellular,
    bool? filesCellular,
    bool? audioCellular,
    bool? photosRoaming,
    bool? videosRoaming,
    bool? filesRoaming,
    bool? audioRoaming,
  }) async {
    final current = storageSettings;
    final updated = current.copyWith(
      autoDownloadPhotosOnWifi: photosWifi,
      autoDownloadVideosOnWifi: videosWifi,
      autoDownloadFilesOnWifi: filesWifi,
      autoDownloadAudioOnWifi: audioWifi,
      autoDownloadPhotosOnCellular: photosCellular,
      autoDownloadVideosOnCellular: videosCellular,
      autoDownloadFilesOnCellular: filesCellular,
      autoDownloadAudioOnCellular: audioCellular,
      autoDownloadPhotosOnRoaming: photosRoaming,
      autoDownloadVideosOnRoaming: videosRoaming,
      autoDownloadFilesOnRoaming: filesRoaming,
      autoDownloadAudioOnRoaming: audioRoaming,
    );
    await saveStorageSettings(updated);
  }

  /// Обновить путь для загрузок
  Future<void> updateDownloadPath(String? downloadPath) async {
    final current = storageSettings;
    final updated = current.copyWith(downloadPath: downloadPath);
    await saveStorageSettings(updated);
  }

  // ============ Настройки энергосбережения ============

  /// Получить настройки энергосбережения
  PowerSavingSettings get powerSavingSettings => _cachedPowerSavingSettings ?? PowerSavingSettings.defaults();

  /// Сохранить настройки энергосбережения
  Future<void> savePowerSavingSettings(PowerSavingSettings settings) async {
    _cachedPowerSavingSettings = settings;
    await _prefs.setString(_powerSavingKey, jsonEncode(settings.toJson()));
  }

  /// Обновить настройки энергосбережения
  Future<void> updatePowerSavingSettings({
    bool? powerSavingEnabled,
    int? batteryThreshold,
    bool? reduceBackgroundActivity,
    bool? lowerScreenBrightness,
    bool? limitFrameRate,
    bool? disableVibrations,
    bool? disableLocationServices,
  }) async {
    final current = powerSavingSettings;
    final updated = current.copyWith(
      powerSavingEnabled: powerSavingEnabled,
      batteryThreshold: batteryThreshold,
      reduceBackgroundActivity: reduceBackgroundActivity,
      lowerScreenBrightness: lowerScreenBrightness,
      limitFrameRate: limitFrameRate,
      disableVibrations: disableVibrations,
      disableLocationServices: disableLocationServices,
    );
    await savePowerSavingSettings(updated);
  }

  // ============ Liquid Glass дизайн ============

  /// Проверяет, поддерживает ли текущая платформа Liquid Glass
  /// Доступно только на Android, iOS и macOS
  static bool get isLiquidGlassSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  /// Получить настройку Liquid Glass дизайна (устаревший, для совместимости)
  bool get liquidGlassDesign => _cachedLiquidGlassDesign ?? false;

  /// Получить режим стекла
  GlassMode get glassMode => _cachedGlassMode ?? GlassMode.disabled;

  /// Сохранить режим стекла
  Future<void> saveGlassMode(GlassMode mode) async {
    _cachedGlassMode = mode;
    _cachedLiquidGlassDesign = mode != GlassMode.disabled;
    await _prefs.setInt(_glassModeKey, mode.index);
    await _prefs.setBool(_liquidGlassDesignKey, mode != GlassMode.disabled);
  }

  /// Сохранить настройку Liquid Glass дизайна (устаревший, для совместимости)
  Future<void> saveLiquidGlassDesign(bool enabled) async {
    _cachedLiquidGlassDesign = enabled;
    _cachedGlassMode = enabled ? GlassMode.full : GlassMode.disabled;
    await _prefs.setBool(_liquidGlassDesignKey, enabled);
    await _prefs.setInt(_glassModeKey, _cachedGlassMode!.index);
  }

  /// Получить значение угла освещения при ручной настройке (в градусах)
  double get manualLightAngle => _cachedManualLightAngle ?? 62.0;

  /// Сохранить значение угла освещения при ручной настройке (в градусах)
  Future<void> saveManualLightAngle(double angle) async {
    _cachedManualLightAngle = angle;
    await _prefs.setDouble(_manualLightAngleKey, angle);
  }

  /// Получить степень размытия стекла (блюр)
  double get glassBlur => _cachedGlassBlur ?? 8.0;

  /// Сохранить степень размытия стекла (блюр)
  Future<void> saveGlassBlur(double blur) async {
    _cachedGlassBlur = blur;
    await _prefs.setDouble(_glassBlurKey, blur);
  }

  // ============ Глобальные настройки уведомлений ============

  /// Получить глобальные настройки уведомлений
  GlobalNotificationSettings get notificationSettings =>
      _cachedNotificationSettings ?? GlobalNotificationSettings.defaults();

  /// Сохранить глобальные настройки уведомлений
  Future<void> saveNotificationSettings(GlobalNotificationSettings settings) async {
    _cachedNotificationSettings = settings;
    await _prefs.setString(_notificationSettingsKey, jsonEncode(settings.toJson()));
  }

  // ============ Per-chat настройки уведомлений ============

  /// Получить per-chat настройки уведомлений
  ChatNotificationSettings? getChatNotificationSettings(String chatId) {
    return _cachedChatNotificationSettings?[chatId];
  }

  /// Получить все per-chat настройки уведомлений
  Map<String, ChatNotificationSettings> get allChatNotificationSettings =>
      _cachedChatNotificationSettings ?? {};

  /// Сохранить per-chat настройки уведомлений
  Future<void> saveChatNotificationSettings(String chatId, ChatNotificationSettings settings) async {
    _cachedChatNotificationSettings ??= {};
    _cachedChatNotificationSettings![chatId] = settings;
    await _prefs.setString(
      _chatNotificationSettingsKey,
      jsonEncode(_cachedChatNotificationSettings!.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Удалить per-chat настройки уведомлений (вернуть к глобальным)
  Future<void> removeChatNotificationSettings(String chatId) async {
    _cachedChatNotificationSettings?.remove(chatId);
    final data = _cachedChatNotificationSettings ?? {};
    await _prefs.setString(
      _chatNotificationSettingsKey,
      jsonEncode(data.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Сбросить все per-chat настройки уведомлений
  Future<void> resetAllChatNotificationSettings() async {
    _cachedChatNotificationSettings = {};
    await _prefs.remove(_chatNotificationSettingsKey);
  }

  /// Получить эффективные настройки для чата (per-chat или глобальные)
  EffectiveChatSettings getEffectiveChatSettings(String chatId) {
    final global = notificationSettings;
    final chat = getChatNotificationSettings(chatId);

    if (chat == null) {
      return EffectiveChatSettings(
        muteState: MuteState.notMuted,
        previewEnabled: global.contentPreview,
        soundEnabled: true,
        soundUri: null,
        vibration: VibrationPattern.default_,
        mentionsOnly: false,
        keywords: [],
      );
    }

    return EffectiveChatSettings(
      muteState: chat.muteState,
      previewEnabled: chat.previewEnabled,
      soundEnabled: chat.soundEnabled ?? true,
      soundUri: chat.soundUri,
      vibration: chat.vibration ?? VibrationPattern.default_,
      mentionsOnly: chat.mentionsOnly,
      keywords: chat.keywords,
    );
  }

  /// Очистить все настройки (при выходе из аккаунта)
  Future<void> clearAllSettings() async {
    _cachedProfile = null;
    _cachedFolders = null;
    _cachedStorageSettings = null;
    _cachedPowerSavingSettings = null;
    _cachedLiquidGlassDesign = null;
    _cachedGlassMode = null;
    _cachedManualLightAngle = null;
    _cachedGlassBlur = null;
    _cachedNotificationSettings = null;
    _cachedChatNotificationSettings = null;
    await _prefs.remove(_profileKey);
    await _prefs.remove(_foldersKey);
    await _prefs.remove(_storageSettingsKey);
    await _prefs.remove(_powerSavingKey);
    await _prefs.remove(_liquidGlassDesignKey);
    await _prefs.remove(_glassModeKey);
    await _prefs.remove(_manualLightAngleKey);
    await _prefs.remove(_glassBlurKey);
    await _prefs.remove(_notificationSettingsKey);
    await _prefs.remove(_chatNotificationSettingsKey);
  }
}

/// Модель профиля пользователя
class UserProfile {
  final String name;
  final String surname;
  final String username;
  final String email;
  final String phone;
  final String? avatarUrl;

  UserProfile({
    required this.name,
    required this.surname,
    required this.username,
    required this.email,
    required this.phone,
    this.avatarUrl,
  });

  UserProfile copyWith({
    String? name,
    String? surname,
    String? username,
    String? email,
    String? phone,
    String? avatarUrl,
  }) {
    return UserProfile(
      name: name ?? this.name,
      surname: surname ?? this.surname,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'surname': surname,
      'username': username,
      'email': email,
      'phone': phone,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? json['display_name'] ?? '',
      surname: json['surname'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
    );
  }
}

/// Модель настроек хранилища
class StorageSettings {
  // Auto-download settings for Wi-Fi
  final bool autoDownloadPhotosOnWifi;
  final bool autoDownloadVideosOnWifi;
  final bool autoDownloadFilesOnWifi;
  final bool autoDownloadAudioOnWifi;

  // Auto-download settings for Cellular
  final bool autoDownloadPhotosOnCellular;
  final bool autoDownloadVideosOnCellular;
  final bool autoDownloadFilesOnCellular;
  final bool autoDownloadAudioOnCellular;

  // Auto-download settings for Roaming
  final bool autoDownloadPhotosOnRoaming;
  final bool autoDownloadVideosOnRoaming;
  final bool autoDownloadFilesOnRoaming;
  final bool autoDownloadAudioOnRoaming;

  StorageSettings({
    required this.autoDownloadPhotosOnWifi,
    required this.autoDownloadVideosOnWifi,
    required this.autoDownloadFilesOnWifi,
    required this.autoDownloadAudioOnWifi,
    required this.autoDownloadPhotosOnCellular,
    required this.autoDownloadVideosOnCellular,
    required this.autoDownloadFilesOnCellular,
    required this.autoDownloadAudioOnCellular,
    required this.autoDownloadPhotosOnRoaming,
    required this.autoDownloadVideosOnRoaming,
    required this.autoDownloadFilesOnRoaming,
    required this.autoDownloadAudioOnRoaming,
    this.downloadPath,
  });

  // Download path for saving files
  final String? downloadPath;

  factory StorageSettings.defaults() {
    return StorageSettings(
      autoDownloadPhotosOnWifi: true,
      autoDownloadVideosOnWifi: false,
      autoDownloadFilesOnWifi: true,
      autoDownloadAudioOnWifi: false,
      autoDownloadPhotosOnCellular: false,
      autoDownloadVideosOnCellular: false,
      autoDownloadFilesOnCellular: false,
      autoDownloadAudioOnCellular: false,
      autoDownloadPhotosOnRoaming: false,
      autoDownloadVideosOnRoaming: false,
      autoDownloadFilesOnRoaming: false,
      autoDownloadAudioOnRoaming: false,
    );
    }
  
    Map<String, dynamic> toJson() {
      return {
        'autoDownloadPhotosOnWifi': autoDownloadPhotosOnWifi,
        'autoDownloadVideosOnWifi': autoDownloadVideosOnWifi,
        'autoDownloadFilesOnWifi': autoDownloadFilesOnWifi,
        'autoDownloadAudioOnWifi': autoDownloadAudioOnWifi,
        'autoDownloadPhotosOnCellular': autoDownloadPhotosOnCellular,
        'autoDownloadVideosOnCellular': autoDownloadVideosOnCellular,
        'autoDownloadFilesOnCellular': autoDownloadFilesOnCellular,
        'autoDownloadAudioOnCellular': autoDownloadAudioOnCellular,
        'autoDownloadPhotosOnRoaming': autoDownloadPhotosOnRoaming,
        'autoDownloadVideosOnRoaming': autoDownloadVideosOnRoaming,
        'autoDownloadFilesOnRoaming': autoDownloadFilesOnRoaming,
        'autoDownloadAudioOnRoaming': autoDownloadAudioOnRoaming,
        'downloadPath': downloadPath,
      };
    }
  
    factory StorageSettings.fromJson(Map<String, dynamic> json) {
      return StorageSettings(
        autoDownloadPhotosOnWifi: json['autoDownloadPhotosOnWifi'] ?? true,
        autoDownloadVideosOnWifi: json['autoDownloadVideosOnWifi'] ?? false,
        autoDownloadFilesOnWifi: json['autoDownloadFilesOnWifi'] ?? true,
        autoDownloadAudioOnWifi: json['autoDownloadAudioOnWifi'] ?? false,
        autoDownloadPhotosOnCellular: json['autoDownloadPhotosOnCellular'] ?? false,
        autoDownloadVideosOnCellular: json['autoDownloadVideosOnCellular'] ?? false,
        autoDownloadFilesOnCellular: json['autoDownloadFilesOnCellular'] ?? false,
        autoDownloadAudioOnCellular: json['autoDownloadAudioOnCellular'] ?? false,
        autoDownloadPhotosOnRoaming: json['autoDownloadPhotosOnRoaming'] ?? false,
        autoDownloadVideosOnRoaming: json['autoDownloadVideosOnRoaming'] ?? false,
        autoDownloadFilesOnRoaming: json['autoDownloadFilesOnRoaming'] ?? false,
        autoDownloadAudioOnRoaming: json['autoDownloadAudioOnRoaming'] ?? false,
        downloadPath: json['downloadPath'],
      );
    }
  
    StorageSettings copyWith({
      bool? autoDownloadPhotosOnWifi,
      bool? autoDownloadVideosOnWifi,
      bool? autoDownloadFilesOnWifi,
      bool? autoDownloadAudioOnWifi,
      bool? autoDownloadPhotosOnCellular,
      bool? autoDownloadVideosOnCellular,
      bool? autoDownloadFilesOnCellular,
      bool? autoDownloadAudioOnCellular,
      bool? autoDownloadPhotosOnRoaming,
      bool? autoDownloadVideosOnRoaming,
      bool? autoDownloadFilesOnRoaming,
      bool? autoDownloadAudioOnRoaming,
      String? downloadPath,
    }) {
      return StorageSettings(
        autoDownloadPhotosOnWifi: autoDownloadPhotosOnWifi ?? this.autoDownloadPhotosOnWifi,
        autoDownloadVideosOnWifi: autoDownloadVideosOnWifi ?? this.autoDownloadVideosOnWifi,
        autoDownloadFilesOnWifi: autoDownloadFilesOnWifi ?? this.autoDownloadFilesOnWifi,
        autoDownloadAudioOnWifi: autoDownloadAudioOnWifi ?? this.autoDownloadAudioOnWifi,
        autoDownloadPhotosOnCellular: autoDownloadPhotosOnCellular ?? this.autoDownloadPhotosOnCellular,
        autoDownloadVideosOnCellular: autoDownloadVideosOnCellular ?? this.autoDownloadVideosOnCellular,
        autoDownloadFilesOnCellular: autoDownloadFilesOnCellular ?? this.autoDownloadFilesOnCellular,
        autoDownloadAudioOnCellular: autoDownloadAudioOnCellular ?? this.autoDownloadAudioOnCellular,
        autoDownloadPhotosOnRoaming: autoDownloadPhotosOnRoaming ?? this.autoDownloadPhotosOnRoaming,
        autoDownloadVideosOnRoaming: autoDownloadVideosOnRoaming ?? this.autoDownloadVideosOnRoaming,
        autoDownloadFilesOnRoaming: autoDownloadFilesOnRoaming ?? this.autoDownloadFilesOnRoaming,
        autoDownloadAudioOnRoaming: autoDownloadAudioOnRoaming ?? this.autoDownloadAudioOnRoaming,
        downloadPath: downloadPath ?? this.downloadPath,
      );
    }
  }

/// Модель настроек энергосбережения
class PowerSavingSettings {
  final bool powerSavingEnabled;
  final int batteryThreshold;
  final bool reduceBackgroundActivity;
  final bool lowerScreenBrightness;
  final bool limitFrameRate;
  final bool disableVibrations;
  final bool disableLocationServices;

  PowerSavingSettings({
    required this.powerSavingEnabled,
    required this.batteryThreshold,
    required this.reduceBackgroundActivity,
    required this.lowerScreenBrightness,
    required this.limitFrameRate,
    required this.disableVibrations,
    required this.disableLocationServices,
  });

  factory PowerSavingSettings.defaults() {
    return PowerSavingSettings(
      powerSavingEnabled: false,
      batteryThreshold: 20,
      reduceBackgroundActivity: false,
      lowerScreenBrightness: false,
      limitFrameRate: false,
      disableVibrations: false,
      disableLocationServices: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'powerSavingEnabled': powerSavingEnabled,
      'batteryThreshold': batteryThreshold,
      'reduceBackgroundActivity': reduceBackgroundActivity,
      'lowerScreenBrightness': lowerScreenBrightness,
      'limitFrameRate': limitFrameRate,
      'disableVibrations': disableVibrations,
      'disableLocationServices': disableLocationServices,
    };
  }

  factory PowerSavingSettings.fromJson(Map<String, dynamic> json) {
    return PowerSavingSettings(
      powerSavingEnabled: json['powerSavingEnabled'] ?? false,
      batteryThreshold: json['batteryThreshold'] ?? 20,
      reduceBackgroundActivity: json['reduceBackgroundActivity'] ?? false,
      lowerScreenBrightness: json['lowerScreenBrightness'] ?? false,
      limitFrameRate: json['limitFrameRate'] ?? false,
      disableVibrations: json['disableVibrations'] ?? false,
      disableLocationServices: json['disableLocationServices'] ?? false,
    );
  }

  PowerSavingSettings copyWith({
    bool? powerSavingEnabled,
    int? batteryThreshold,
    bool? reduceBackgroundActivity,
    bool? lowerScreenBrightness,
    bool? limitFrameRate,
    bool? disableVibrations,
    bool? disableLocationServices,
  }) {
    return PowerSavingSettings(
      powerSavingEnabled: powerSavingEnabled ?? this.powerSavingEnabled,
      batteryThreshold: batteryThreshold ?? this.batteryThreshold,
      reduceBackgroundActivity: reduceBackgroundActivity ?? this.reduceBackgroundActivity,
      lowerScreenBrightness: lowerScreenBrightness ?? this.lowerScreenBrightness,
      limitFrameRate: limitFrameRate ?? this.limitFrameRate,
      disableVibrations: disableVibrations ?? this.disableVibrations,
      disableLocationServices: disableLocationServices ?? this.disableLocationServices,
    );
  }
}

/// Паттерн вибрации для уведомлений
enum VibrationPattern {
  default_,
  none,
  short,
  long,
  doubleShort,
  tripleShort,
}

/// Состояние мьюта чата
enum MuteState {
  notMuted,
  muted,
  mutedUntil,
}

/// Режим подсчёта для бейджа
enum BadgeMode {
  messages,
  chats,
}

/// Глобальные настройки уведомлений пользователя
class GlobalNotificationSettings {
  // Главный переключатель
  final bool notificationsEnabled;

  // Приватные чаты
  final bool privateChatNotifications;
  final bool privateChatPreview;
  final bool privateChatSound;
  final String? privateChatSoundUri;
  final VibrationPattern privateChatVibration;

  // Групповые чаты
  final bool groupChatNotifications;
  final bool groupChatPreview;
  final bool groupChatSound;
  final String? groupChatSoundUri;
  final VibrationPattern groupChatVibration;

  // Каналы
  final bool channelNotifications;
  final bool channelPreview;
  final bool channelSound;
  final String? channelSoundUri;
  final VibrationPattern channelVibration;

  // Звонки
  final bool callNotifications;
  final bool callSound;
  final bool callVibration;
  final String? callRingtone;

  // Упоминания
  final bool mentionsNotifications;
  final bool keywordsNotifications;

  // Поведение и бейдж
  final bool badgeEnabled;
  final BadgeMode badgeMode;
  final bool popupEnabled;
  final bool contentPreview;
  final bool includeMutedChats;
  final bool accountNotifications;

  // In-App уведомления
  final bool inAppSounds;
  final bool inAppVibrate;
  final bool inAppPreview;
  final bool inAppChatSounds;

  // Повтор уведомлений (в минутах, 0 = выкл)
  final int repeatNotifications;

  GlobalNotificationSettings({
    this.notificationsEnabled = true,
    this.privateChatNotifications = true,
    this.privateChatPreview = true,
    this.privateChatSound = true,
    this.privateChatSoundUri,
    this.privateChatVibration = VibrationPattern.default_,
    this.groupChatNotifications = true,
    this.groupChatPreview = true,
    this.groupChatSound = true,
    this.groupChatSoundUri,
    this.groupChatVibration = VibrationPattern.default_,
    this.channelNotifications = true,
    this.channelPreview = true,
    this.channelSound = true,
    this.channelSoundUri,
    this.channelVibration = VibrationPattern.default_,
    this.callNotifications = true,
    this.callSound = true,
    this.callVibration = true,
    this.callRingtone,
    this.mentionsNotifications = true,
    this.keywordsNotifications = false,
    this.badgeEnabled = true,
    this.badgeMode = BadgeMode.messages,
    this.popupEnabled = true,
    this.contentPreview = true,
    this.includeMutedChats = false,
    this.accountNotifications = true,
    this.inAppSounds = true,
    this.inAppVibrate = true,
    this.inAppPreview = true,
    this.inAppChatSounds = true,
    this.repeatNotifications = 0,
  });

  factory GlobalNotificationSettings.defaults() => GlobalNotificationSettings();

  Map<String, dynamic> toJson() => {
    'notificationsEnabled': notificationsEnabled,
    'privateChatNotifications': privateChatNotifications,
    'privateChatPreview': privateChatPreview,
    'privateChatSound': privateChatSound,
    'privateChatSoundUri': privateChatSoundUri,
    'privateChatVibration': privateChatVibration.index,
    'groupChatNotifications': groupChatNotifications,
    'groupChatPreview': groupChatPreview,
    'groupChatSound': groupChatSound,
    'groupChatSoundUri': groupChatSoundUri,
    'groupChatVibration': groupChatVibration.index,
    'channelNotifications': channelNotifications,
    'channelPreview': channelPreview,
    'channelSound': channelSound,
    'channelSoundUri': channelSoundUri,
    'channelVibration': channelVibration.index,
    'callNotifications': callNotifications,
    'callSound': callSound,
    'callVibration': callVibration,
    'callRingtone': callRingtone,
    'mentionsNotifications': mentionsNotifications,
    'keywordsNotifications': keywordsNotifications,
    'badgeEnabled': badgeEnabled,
    'badgeMode': badgeMode.index,
    'popupEnabled': popupEnabled,
    'contentPreview': contentPreview,
    'includeMutedChats': includeMutedChats,
    'accountNotifications': accountNotifications,
    'inAppSounds': inAppSounds,
    'inAppVibrate': inAppVibrate,
    'inAppPreview': inAppPreview,
    'inAppChatSounds': inAppChatSounds,
    'repeatNotifications': repeatNotifications,
  };

  Map<String, dynamic> toServerJson() => {
    'notifications_enabled': notificationsEnabled,
    'private_chat_notifications': privateChatNotifications,
    'private_chat_preview': privateChatPreview,
    'private_chat_sound': privateChatSound,
    'private_chat_sound_uri': privateChatSoundUri ?? '',
    'private_chat_vibration': _vibrationToString(privateChatVibration),
    'group_chat_notifications': groupChatNotifications,
    'group_chat_preview': groupChatPreview,
    'group_chat_sound': groupChatSound,
    'group_chat_sound_uri': groupChatSoundUri ?? '',
    'group_chat_vibration': _vibrationToString(groupChatVibration),
    'channel_notifications': channelNotifications,
    'channel_preview': channelPreview,
    'channel_sound': channelSound,
    'channel_sound_uri': channelSoundUri ?? '',
    'channel_vibration': _vibrationToString(channelVibration),
    'call_notifications': callNotifications,
    'call_sound': callSound,
    'call_vibration': callVibration,
    'call_ringtone': callRingtone ?? '',
    'mentions_notifications': mentionsNotifications,
    'keywords_notifications': keywordsNotifications,
    'badge_enabled': badgeEnabled,
    'badge_mode': badgeMode == BadgeMode.chats ? 'chats' : 'messages',
    'popup_enabled': popupEnabled,
    'content_preview': contentPreview,
    'include_muted_chats': includeMutedChats,
    'account_notifications': accountNotifications,
    'in_app_sounds': inAppSounds,
    'in_app_vibrate': inAppVibrate,
    'in_app_preview': inAppPreview,
    'in_app_chat_sounds': inAppChatSounds,
    'repeat_notifications': repeatNotifications,
  };

  factory GlobalNotificationSettings.fromJson(Map<String, dynamic> json) {
    return GlobalNotificationSettings(
      notificationsEnabled: json['notificationsEnabled'] ?? json['notifications_enabled'] ?? true,
      privateChatNotifications: json['privateChatNotifications'] ?? json['private_chat_notifications'] ?? true,
      privateChatPreview: json['privateChatPreview'] ?? json['private_chat_preview'] ?? true,
      privateChatSound: json['privateChatSound'] ?? json['private_chat_sound'] ?? true,
      privateChatSoundUri: json['privateChatSoundUri'] ?? json['private_chat_sound_uri'],
      privateChatVibration: _parseVibration(json['privateChatVibration'] ?? json['private_chat_vibration']),
      groupChatNotifications: json['groupChatNotifications'] ?? json['group_chat_notifications'] ?? true,
      groupChatPreview: json['groupChatPreview'] ?? json['group_chat_preview'] ?? true,
      groupChatSound: json['groupChatSound'] ?? json['group_chat_sound'] ?? true,
      groupChatSoundUri: json['groupChatSoundUri'] ?? json['group_chat_sound_uri'],
      groupChatVibration: _parseVibration(json['groupChatVibration'] ?? json['group_chat_vibration']),
      channelNotifications: json['channelNotifications'] ?? json['channel_notifications'] ?? true,
      channelPreview: json['channelPreview'] ?? json['channel_preview'] ?? true,
      channelSound: json['channelSound'] ?? json['channel_sound'] ?? true,
      channelSoundUri: json['channelSoundUri'] ?? json['channel_sound_uri'],
      channelVibration: _parseVibration(json['channelVibration'] ?? json['channel_vibration']),
      callNotifications: json['callNotifications'] ?? json['call_notifications'] ?? true,
      callSound: json['callSound'] ?? json['call_sound'] ?? true,
      callVibration: json['callVibration'] ?? json['call_vibration'] ?? true,
      callRingtone: json['callRingtone'] ?? json['call_ringtone'],
      mentionsNotifications: json['mentionsNotifications'] ?? json['mentions_notifications'] ?? true,
      keywordsNotifications: json['keywordsNotifications'] ?? json['keywords_notifications'] ?? false,
      badgeEnabled: json['badgeEnabled'] ?? json['badge_enabled'] ?? true,
      badgeMode: _parseBadgeMode(json['badgeMode'] ?? json['badge_mode']),
      popupEnabled: json['popupEnabled'] ?? json['popup_enabled'] ?? true,
      contentPreview: json['contentPreview'] ?? json['content_preview'] ?? true,
      includeMutedChats: json['includeMutedChats'] ?? json['include_muted_chats'] ?? false,
      accountNotifications: json['accountNotifications'] ?? json['account_notifications'] ?? true,
      inAppSounds: json['inAppSounds'] ?? json['in_app_sounds'] ?? true,
      inAppVibrate: json['inAppVibrate'] ?? json['in_app_vibrate'] ?? true,
      inAppPreview: json['inAppPreview'] ?? json['in_app_preview'] ?? true,
      inAppChatSounds: json['inAppChatSounds'] ?? json['in_app_chat_sounds'] ?? true,
      repeatNotifications: json['repeatNotifications'] ?? json['repeat_notifications'] ?? 0,
    );
  }

  static VibrationPattern _parseVibration(dynamic value) {
    if (value is int && value >= 0 && value < VibrationPattern.values.length) {
      return VibrationPattern.values[value];
    }
    if (value is String) {
      switch (value) {
        case 'none':
          return VibrationPattern.none;
        case 'short':
          return VibrationPattern.short;
        case 'long':
          return VibrationPattern.long;
        case 'double_short':
          return VibrationPattern.doubleShort;
        case 'triple_short':
          return VibrationPattern.tripleShort;
        default:
          return VibrationPattern.default_;
      }
    }
    return VibrationPattern.default_;
  }

  static String _vibrationToString(VibrationPattern pattern) {
    switch (pattern) {
      case VibrationPattern.none:
        return 'none';
      case VibrationPattern.short:
        return 'short';
      case VibrationPattern.long:
        return 'long';
      case VibrationPattern.doubleShort:
        return 'double_short';
      case VibrationPattern.tripleShort:
        return 'triple_short';
      default:
        return 'default';
    }
  }

  static BadgeMode _parseBadgeMode(dynamic value) {
    if (value == 'chats' || value == 1) return BadgeMode.chats;
    return BadgeMode.messages;
  }

  GlobalNotificationSettings copyWith({
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
  }) {
    return GlobalNotificationSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      privateChatNotifications: privateChatNotifications ?? this.privateChatNotifications,
      privateChatPreview: privateChatPreview ?? this.privateChatPreview,
      privateChatSound: privateChatSound ?? this.privateChatSound,
      privateChatSoundUri: privateChatSoundUri ?? this.privateChatSoundUri,
      privateChatVibration: privateChatVibration ?? this.privateChatVibration,
      groupChatNotifications: groupChatNotifications ?? this.groupChatNotifications,
      groupChatPreview: groupChatPreview ?? this.groupChatPreview,
      groupChatSound: groupChatSound ?? this.groupChatSound,
      groupChatSoundUri: groupChatSoundUri ?? this.groupChatSoundUri,
      groupChatVibration: groupChatVibration ?? this.groupChatVibration,
      channelNotifications: channelNotifications ?? this.channelNotifications,
      channelPreview: channelPreview ?? this.channelPreview,
      channelSound: channelSound ?? this.channelSound,
      channelSoundUri: channelSoundUri ?? this.channelSoundUri,
      channelVibration: channelVibration ?? this.channelVibration,
      callNotifications: callNotifications ?? this.callNotifications,
      callSound: callSound ?? this.callSound,
      callVibration: callVibration ?? this.callVibration,
      callRingtone: callRingtone ?? this.callRingtone,
      mentionsNotifications: mentionsNotifications ?? this.mentionsNotifications,
      keywordsNotifications: keywordsNotifications ?? this.keywordsNotifications,
      badgeEnabled: badgeEnabled ?? this.badgeEnabled,
      badgeMode: badgeMode ?? this.badgeMode,
      popupEnabled: popupEnabled ?? this.popupEnabled,
      contentPreview: contentPreview ?? this.contentPreview,
      includeMutedChats: includeMutedChats ?? this.includeMutedChats,
      accountNotifications: accountNotifications ?? this.accountNotifications,
      inAppSounds: inAppSounds ?? this.inAppSounds,
      inAppVibrate: inAppVibrate ?? this.inAppVibrate,
      inAppPreview: inAppPreview ?? this.inAppPreview,
      inAppChatSounds: inAppChatSounds ?? this.inAppChatSounds,
      repeatNotifications: repeatNotifications ?? this.repeatNotifications,
    );
  }
}

/// Настройки уведомлений для конкретного чата
class ChatNotificationSettings {
  final String chatId;
  final MuteState muteState;
  final DateTime? muteUntil;
  final bool previewEnabled;
  final bool? soundEnabled;
  final String? soundUri;
  final VibrationPattern? vibration;
  final bool mentionsOnly;
  final List<String> keywords;

  const ChatNotificationSettings({
    required this.chatId,
    this.muteState = MuteState.notMuted,
    this.muteUntil,
    this.previewEnabled = true,
    this.soundEnabled,
    this.soundUri,
    this.vibration,
    this.mentionsOnly = false,
    this.keywords = const [],
  });

  Map<String, dynamic> toJson() => {
    'chatId': chatId,
    'muteState': muteState.index,
    'muteUntil': muteUntil?.toIso8601String(),
    'previewEnabled': previewEnabled,
    'soundEnabled': soundEnabled,
    'soundUri': soundUri,
    'vibration': vibration?.index,
    'mentionsOnly': mentionsOnly,
    'keywords': keywords,
  };

  Map<String, dynamic> toServerJson() => {
    'chat_id': chatId,
    'mute_state': muteState == MuteState.muted
        ? 'muted'
        : (muteState == MuteState.mutedUntil ? 'muted_until' : 'not_muted'),
    'mute_until': muteUntil?.toIso8601String(),
    'preview_enabled': previewEnabled,
    'sound_enabled': soundEnabled,
    'sound_uri': soundUri ?? '',
    'vibration': vibration != null
        ? GlobalNotificationSettings._vibrationToString(vibration!)
        : '',
    'mentions_only': mentionsOnly,
    'keywords': keywords,
  };

  factory ChatNotificationSettings.fromJson(Map<String, dynamic> json) {
    return ChatNotificationSettings(
      chatId: json['chatId']?.toString() ?? json['chat_id']?.toString() ?? '',
      muteState: _parseMuteState(json['muteState'] ?? json['mute_state']),
      muteUntil: json['muteUntil'] != null
          ? DateTime.tryParse(json['muteUntil'])
          : (json['mute_until'] != null ? DateTime.tryParse(json['mute_until']) : null),
      previewEnabled: json['previewEnabled'] ?? json['preview_enabled'] ?? true,
      soundEnabled: json['soundEnabled'] ?? json['sound_enabled'],
      soundUri: json['soundUri'] ?? json['sound_uri'],
      vibration: json['vibration'] != null
          ? GlobalNotificationSettings._parseVibration(json['vibration'])
          : null,
      mentionsOnly: json['mentionsOnly'] ?? json['mentions_only'] ?? false,
      keywords: json['keywords'] != null ? List<String>.from(json['keywords']) : [],
    );
  }

  static MuteState _parseMuteState(dynamic value) {
    if (value is int && value >= 0 && value < MuteState.values.length) {
      return MuteState.values[value];
    }
    if (value == 'muted') return MuteState.muted;
    if (value == 'muted_until') return MuteState.mutedUntil;
    return MuteState.notMuted;
  }

  ChatNotificationSettings copyWith({
    String? chatId,
    MuteState? muteState,
    DateTime? muteUntil,
    bool? previewEnabled,
    bool? soundEnabled,
    String? soundUri,
    VibrationPattern? vibration,
    bool? mentionsOnly,
    List<String>? keywords,
  }) {
    return ChatNotificationSettings(
      chatId: chatId ?? this.chatId,
      muteState: muteState ?? this.muteState,
      muteUntil: muteUntil ?? this.muteUntil,
      previewEnabled: previewEnabled ?? this.previewEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      soundUri: soundUri ?? this.soundUri,
      vibration: vibration ?? this.vibration,
      mentionsOnly: mentionsOnly ?? this.mentionsOnly,
      keywords: keywords ?? this.keywords,
    );
  }
}

/// Исключение в настройках уведомлений с метаданными чата
class ChatNotificationException {
  final ChatNotificationSettings settings;
  final String chatType;
  final String chatTitle;
  final String? avatarUrl;

  const ChatNotificationException({
    required this.settings,
    required this.chatType,
    required this.chatTitle,
    this.avatarUrl,
  });

  factory ChatNotificationException.fromJson(Map<String, dynamic> json) {
    return ChatNotificationException(
      settings: ChatNotificationSettings.fromJson(json),
      chatType: json['chat_type'] ?? 'private',
      chatTitle: json['chat_title'] ?? 'Chat',
      avatarUrl: json['avatar_url'],
    );
  }
}

/// Эффективные настройки чата (результат слияния глобальных и per-chat)
class EffectiveChatSettings {
  final MuteState muteState;
  final bool previewEnabled;
  final bool soundEnabled;
  final String? soundUri;
  final VibrationPattern vibration;
  final bool mentionsOnly;
  final List<String> keywords;

  const EffectiveChatSettings({
    required this.muteState,
    required this.previewEnabled,
    required this.soundEnabled,
    this.soundUri,
    required this.vibration,
    required this.mentionsOnly,
    required this.keywords,
  });

  bool get isMuted => muteState != MuteState.notMuted;
}

// ============ Privacy Settings Models ============

/// Варианты видимости для правил приватности
enum PrivacyVisibility {
  everybody,
  contacts,
  nobody;

  String toJson() => name;
  static PrivacyVisibility fromJson(String value) =>
      PrivacyVisibility.values.firstWhere((e) => e.name == value,
          orElse: () => PrivacyVisibility.contacts);
}

/// Расширенные настройки приватности
class PrivacySettings {
  final PrivacyVisibility lastSeenVisibility;
  final PrivacyVisibility profilePhotoVisibility;
  final PrivacyVisibility phoneNumberVisibility;
  final PrivacyVisibility phoneCallPrivacy;
  final PrivacyVisibility callPrivacy;
  final PrivacyVisibility groupsChannelsPrivacy;
  final PrivacyVisibility bioVisibility;
  final PrivacyVisibility forwardedMessages; // everybody=show sender, nobody=anonymous
  final bool showOnlineStatus;
  final bool showReadReceipts;

  const PrivacySettings({
    this.lastSeenVisibility = PrivacyVisibility.contacts,
    this.profilePhotoVisibility = PrivacyVisibility.everybody,
    this.phoneNumberVisibility = PrivacyVisibility.contacts,
    this.phoneCallPrivacy = PrivacyVisibility.contacts,
    this.callPrivacy = PrivacyVisibility.everybody,
    this.groupsChannelsPrivacy = PrivacyVisibility.everybody,
    this.bioVisibility = PrivacyVisibility.everybody,
    this.forwardedMessages = PrivacyVisibility.everybody,
    this.showOnlineStatus = true,
    this.showReadReceipts = true,
  });

  PrivacySettings copyWith({
    PrivacyVisibility? lastSeenVisibility,
    PrivacyVisibility? profilePhotoVisibility,
    PrivacyVisibility? phoneNumberVisibility,
    PrivacyVisibility? phoneCallPrivacy,
    PrivacyVisibility? callPrivacy,
    PrivacyVisibility? groupsChannelsPrivacy,
    PrivacyVisibility? bioVisibility,
    PrivacyVisibility? forwardedMessages,
    bool? showOnlineStatus,
    bool? showReadReceipts,
  }) =>
      PrivacySettings(
        lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
        profilePhotoVisibility: profilePhotoVisibility ?? this.profilePhotoVisibility,
        phoneNumberVisibility: phoneNumberVisibility ?? this.phoneNumberVisibility,
        phoneCallPrivacy: phoneCallPrivacy ?? this.phoneCallPrivacy,
        callPrivacy: callPrivacy ?? this.callPrivacy,
        groupsChannelsPrivacy: groupsChannelsPrivacy ?? this.groupsChannelsPrivacy,
        bioVisibility: bioVisibility ?? this.bioVisibility,
        forwardedMessages: forwardedMessages ?? this.forwardedMessages,
        showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
        showReadReceipts: showReadReceipts ?? this.showReadReceipts,
      );

  factory PrivacySettings.fromJson(Map<String, dynamic> json) => PrivacySettings(
        lastSeenVisibility: PrivacyVisibility.fromJson(json['last_seen_visibility'] ?? 'contacts'),
        profilePhotoVisibility: PrivacyVisibility.fromJson(json['profile_photo_visibility'] ?? 'everybody'),
        phoneNumberVisibility: PrivacyVisibility.fromJson(json['phone_number_visibility'] ?? 'contacts'),
        phoneCallPrivacy: PrivacyVisibility.fromJson(json['phone_call_privacy'] ?? 'contacts'),
        callPrivacy: PrivacyVisibility.fromJson(json['call_privacy'] ?? 'everybody'),
        groupsChannelsPrivacy: PrivacyVisibility.fromJson(json['groups_channels_privacy'] ?? 'everybody'),
        bioVisibility: PrivacyVisibility.fromJson(json['bio_visibility'] ?? 'everybody'),
        forwardedMessages: PrivacyVisibility.fromJson(json['forwarded_messages'] ?? 'everybody'),
        showOnlineStatus: json['show_online_status'] ?? true,
        showReadReceipts: json['show_read_receipts'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'last_seen_visibility': lastSeenVisibility.toJson(),
        'profile_photo_visibility': profilePhotoVisibility.toJson(),
        'phone_number_visibility': phoneNumberVisibility.toJson(),
        'phone_call_privacy': phoneCallPrivacy.toJson(),
        'call_privacy': callPrivacy.toJson(),
        'groups_channels_privacy': groupsChannelsPrivacy.toJson(),
        'bio_visibility': bioVisibility.toJson(),
        'forwarded_messages': forwardedMessages.toJson(),
        'show_online_status': showOnlineStatus,
        'show_read_receipts': showReadReceipts,
      };
}

/// Исключение для правила приватности (всегда/никогда для конкретного пользователя)
class PrivacyException {
  final String id;
  final String ruleType;
  final String targetUserId;
  final String targetUserName;
  final String exceptionType; // always / never

  const PrivacyException({
    required this.id,
    required this.ruleType,
    required this.targetUserId,
    required this.targetUserName,
    required this.exceptionType,
  });

  factory PrivacyException.fromJson(Map<String, dynamic> json) => PrivacyException(
        id: json['id'] ?? '',
        ruleType: json['rule_type'] ?? '',
        targetUserId: json['target_user_id'] ?? '',
        targetUserName: json['target_user_name'] ?? '',
        exceptionType: json['exception_type'] ?? 'always',
      );
}

/// Настройки двухэтапной аутентификации
class TwoFactorAuthSettings {
  final bool enabled;
  final bool hasPassword;
  final String recoveryEmail;

  const TwoFactorAuthSettings({
    this.enabled = false,
    this.hasPassword = false,
    this.recoveryEmail = '',
  });

  factory TwoFactorAuthSettings.fromJson(Map<String, dynamic> json) =>
      TwoFactorAuthSettings(
        enabled: json['enabled'] ?? false,
        hasPassword: json['has_password'] ?? false,
        recoveryEmail: json['recovery_email'] ?? '',
      );
}

/// Настройки блокировки приложения
class AppLockSettings {
  final bool hasPin;
  final bool biometricsEnabled;
  final String autoLockTimeout; // immediately, 1min, 5min, 15min, 1hour

  const AppLockSettings({
    this.hasPin = false,
    this.biometricsEnabled = false,
    this.autoLockTimeout = '5min',
  });

  factory AppLockSettings.fromJson(Map<String, dynamic> json) => AppLockSettings(
        hasPin: json['has_pin'] ?? false,
        biometricsEnabled: json['biometrics_enabled'] ?? false,
        autoLockTimeout: json['auto_lock_timeout'] ?? '5min',
      );

  Map<String, dynamic> toJson() => {
        'has_pin': hasPin,
        'biometrics_enabled': biometricsEnabled,
        'auto_lock_timeout': autoLockTimeout,
      };
}

/// Заблокированный пользователь
class BlockedUser {
  final String userId;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String blockedAt;

  const BlockedUser({
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        userId: json['user_id'] ?? '',
        username: json['username'] ?? '',
        displayName: json['display_name'] ?? '',
        avatarUrl: json['avatar_url'],
        blockedAt: json['blocked_at'] ?? '',
      );
}
