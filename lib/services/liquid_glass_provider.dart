import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'glass_mode.dart';
import 'light_angle_mode.dart';
import 'settings_service.dart';

export 'glass_mode.dart';
export 'light_angle_mode.dart';

/// Провайдер для реактивного управления состоянием Liquid Glass дизайна,
/// а также углом освещения и бликов (гироскоп / ручной режим).
///
/// Поддерживает три режима стекла:
/// - [GlassMode.disabled] — классический дизайн без стекла
/// - [GlassMode.lite] — облегчённый стеклянный дизайн (FakeGlass)
/// - [GlassMode.full] — полноценный стеклянный дизайн (LiquidGlass)
///
/// Угол освещения:
/// - [LightAngleMode.gyroscope] — динамический угол на основе акселерометра/гироскопа
/// - [LightAngleMode.manual] — фиксированный угол, задаваемый пользователем (0°..360°)
///
/// Если в iOS включено системное уменьшение движения ("Reduce Motion"),
/// гироскоп автоматически отключается в пользу фиксированного угла (62°).
class LiquidGlassProvider extends ChangeNotifier {
  final SettingsService _settingsService = SettingsService();

  GlassMode _mode = GlassMode.disabled;
  LightAngleMode _lightAngleMode = LightAngleMode.gyroscope;
  double _manualLightAngle = 62.0;
  double _gyroscopeLightAngle = 62.0;
  double _blur = 8.0;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  double _smoothedX = 0.0;
  double _smoothedY = 9.8;

  /// Текущий режим Liquid Glass дизайна.
  /// Всегда [GlassMode.disabled] на неподдерживаемых платформах.
  GlassMode get mode => isSupported ? _mode : GlassMode.disabled;

  /// Включён ли какой-либо стеклянный дизайн (lite или full).
  /// Всегда `false` на неподдерживаемых платформах.
  bool get enabled => isSupported && _mode != GlassMode.disabled;

  /// Включён ли облегчённый режим (FakeGlass).
  bool get isLite => isSupported && _mode == GlassMode.lite;

  /// Включён ли полный режим (LiquidGlass).
  bool get isFull => isSupported && _mode == GlassMode.full;

  /// Доступность Liquid Glass на текущей платформе
  bool get isSupported => SettingsService.isLiquidGlassSupported;

  /// Текущий режим угла освещения (gyroscope / manual)
  LightAngleMode get lightAngleMode => _lightAngleMode;

  /// Угол освещения в ручном режиме (в градусах, 0°..360°)
  double get manualLightAngle => _manualLightAngle;

  /// Динамический угол освещения по гироскопу (в градусах)
  double get gyroscopeLightAngle => _gyroscopeLightAngle;

  /// Степень размытия заднего плана (blur sigma)
  double get blur => _blur;

  /// Эффект размытия заднего плана для передачи в LiquidGlassLens
  LiquidGlassBlur get blurEffect => LiquidGlassBlur(sigmaX: _blur, sigmaY: _blur);

  /// Вычисляет итоговый угол освещения для передачи в шейдеры/виджеты.
  ///
  /// При [reduceMotion] == true (iOS Reduce Motion / Android Remove Animations)
  /// угол блокируется на стандартном 62°, отключая колебания гироскопа.
  double getEffectiveLightAngle({required bool reduceMotion}) {
    if (reduceMotion) {
      return 62.0;
    }
    if (_lightAngleMode == LightAngleMode.manual) {
      return _manualLightAngle;
    }
    return _gyroscopeLightAngle;
  }

  /// Инициализация из SettingsService
  void init() {
    _mode = _settingsService.glassMode;
    // Если платформа не поддерживается, принудительно сбрасываем
    if (!isSupported && _mode != GlassMode.disabled) {
      _mode = GlassMode.disabled;
      _settingsService.saveGlassMode(GlassMode.disabled);
    }
    _lightAngleMode = _settingsService.lightAngleMode;
    _manualLightAngle = _settingsService.manualLightAngle;
    _blur = _settingsService.glassBlur;

    _updateSensorSubscription();
    notifyListeners();
  }

  /// Установить режим Liquid Glass дизайна
  Future<void> setMode(GlassMode value) async {
    if (!isSupported) return; // Запрещаем включение на неподдерживаемых платформах
    if (_mode == value) return;
    _mode = value;
    await _settingsService.saveGlassMode(value);
    _updateSensorSubscription();
    notifyListeners();
  }

  /// Переключить между disabled и последним активным режимом
  Future<void> toggle() async {
    if (_mode == GlassMode.disabled) {
      await setMode(GlassMode.full);
    } else {
      await setMode(GlassMode.disabled);
    }
  }

  /// Переключить режим угла освещения (gyroscope / manual)
  Future<void> setLightAngleMode(LightAngleMode mode) async {
    if (_lightAngleMode == mode) return;
    _lightAngleMode = mode;
    await _settingsService.saveLightAngleMode(mode);
    _updateSensorSubscription();
    notifyListeners();
  }

  /// Задать угол освещения для ручного режима (0°..360°)
  Future<void> setManualLightAngle(double angle) async {
    final clamped = angle.clamp(0.0, 360.0);
    if (_manualLightAngle == clamped) return;
    _manualLightAngle = clamped;
    await _settingsService.saveManualLightAngle(clamped);
    if (_lightAngleMode == LightAngleMode.manual) {
      notifyListeners();
    }
  }

  /// Задать степень размытия стекла (0..30)
  Future<void> setBlur(double blur) async {
    final clamped = blur.clamp(0.0, 30.0);
    if (_blur == clamped) return;
    _blur = clamped;
    await _settingsService.saveGlassBlur(clamped);
    notifyListeners();
  }

  void _updateSensorSubscription() {
    final shouldListen = enabled && _lightAngleMode == LightAngleMode.gyroscope;
    if (shouldListen) {
      if (_accelerometerSubscription == null) {
        try {
          _accelerometerSubscription = accelerometerEventStream().listen(
            _onAccelerometerEvent,
            onError: (e) {
              debugPrint('LiquidGlassProvider: Accelerometer stream error: $e');
              _cancelSensorSubscription();
            },
            cancelOnError: false,
          );
        } catch (e) {
          debugPrint('LiquidGlassProvider: Accelerometer not supported: $e');
        }
      }
    } else {
      _cancelSensorSubscription();
    }
  }

  void _cancelSensorSubscription() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    // Сглаживание экспоненциальным фильтром для устранения мелкого шума
    _smoothedX = _smoothedX * 0.85 + event.x * 0.15;
    _smoothedY = _smoothedY * 0.85 + event.y * 0.15;

    // В портретной ориентации:
    // x ≈ 0, y ≈ 9.8 -> atan2(9.8, 0) = 90° (свет сверху)
    // наклон вправо: x > 0 -> угол смещается к 0° (свет справа)
    // наклон влево: x < 0 -> угол смещается к 180° (свет слева)
    double angle = math.atan2(_smoothedY, _smoothedX) * 180 / math.pi;
    if (angle < 0) {
      angle += 360.0;
    }

    // Уведомляем только при изменении более чем на 0.8 градуса для экономии ресурсов
    if ((angle - _gyroscopeLightAngle).abs() > 0.8) {
      _gyroscopeLightAngle = angle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cancelSensorSubscription();
    super.dispose();
  }
}
