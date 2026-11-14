import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'settings_service.dart';

/// Провайдер энергосбережения, синхронизированный с [SettingsService].
/// Управляет размытием, анимациями, автовоспроизведением медиа, тактильной
/// отдачей и яркостью экрана на мобильных устройствах.
class PowerSavingProvider extends ChangeNotifier {
  PowerSavingProvider._internal();
  static final PowerSavingProvider instance = PowerSavingProvider._internal();
  factory PowerSavingProvider() => instance;

  PowerSavingSettings _settings = PowerSavingSettings.defaults();
  bool _brightnessLowered = false;

  PowerSavingSettings get settings => _settings;

  /// Включён ли общий режим энергосбережения.
  bool get isActive => _settings.powerSavingEnabled;

  /// Разрешены ли шейдеры и размытие Liquid Glass.
  bool get allowBlur => !(isActive && _settings.limitFrameRate);

  /// Разрешены ли сложные анимации интерфейса.
  bool get allowAnimations => !(isActive && _settings.limitFrameRate);

  /// Разрешено ли автовоспроизведение GIF.
  bool get allowAutoplayGif => !(isActive && _settings.reduceBackgroundActivity);

  /// Разрешено ли автовоспроизведение видео.
  bool get allowAutoplayVideo =>
      !(isActive && _settings.reduceBackgroundActivity);

  /// Разрешена ли тактильная отдача (вибрация / haptic feedback).
  bool get allowHaptics => !(isActive && _settings.disableVibrations);

  Future<void> init() async {
    _loadFromSettingsService();
    await _syncScreenBrightness();
    notifyListeners();
  }

  Future<void> reloadForUser() async {
    _loadFromSettingsService();
    await _syncScreenBrightness();
    notifyListeners();
  }

  void _loadFromSettingsService() {
    try {
      _settings = SettingsService().powerSavingSettings;
    } catch (_) {
      _settings = PowerSavingSettings.defaults();
    }
  }

  Future<void> updateSettings({
    bool? powerSavingEnabled,
    int? batteryThreshold,
    bool? reduceBackgroundActivity,
    bool? lowerScreenBrightness,
    bool? limitFrameRate,
    bool? disableVibrations,
    bool? disableLocationServices,
  }) async {
    final settingsService = SettingsService();
    await settingsService.updatePowerSavingSettings(
      powerSavingEnabled: powerSavingEnabled,
      batteryThreshold: batteryThreshold,
      reduceBackgroundActivity: reduceBackgroundActivity,
      lowerScreenBrightness: lowerScreenBrightness,
      limitFrameRate: limitFrameRate,
      disableVibrations: disableVibrations,
      disableLocationServices: disableLocationServices,
    );
    _settings = settingsService.powerSavingSettings;
    await _syncScreenBrightness();
    notifyListeners();
  }

  Future<void> _syncScreenBrightness() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final shouldLower = isActive && _settings.lowerScreenBrightness;
    if (shouldLower && !_brightnessLowered) {
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(0.25);
        _brightnessLowered = true;
      } catch (e) {
        debugPrint('PowerSavingProvider: failed to lower brightness: $e');
      }
    } else if (!shouldLower && _brightnessLowered) {
      try {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
        _brightnessLowered = false;
      } catch (e) {
        debugPrint('PowerSavingProvider: failed to reset brightness: $e');
      }
    }
  }

  @visibleForTesting
  void setSettingsForTest(PowerSavingSettings settings) {
    _settings = settings;
    notifyListeners();
  }
}
