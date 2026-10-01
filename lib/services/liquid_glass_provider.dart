import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'glass_mode.dart';
import 'settings_service.dart';

export 'glass_mode.dart';

/// Провайдер для реактивного управления состоянием Liquid Glass дизайна,
/// а также углом освещения и степенью размытия.
///
/// Поддерживает три режима стекла:
/// - [GlassMode.disabled] — классический дизайн без стекла
/// - [GlassMode.lite] — облегчённый стеклянный дизайн (FakeGlass)
/// - [GlassMode.full] — полноценный стеклянный дизайн (LiquidGlass)
///
/// Угол освещения: фиксированный/настраиваемый угол (по умолчанию 62°).
class LiquidGlassProvider extends ChangeNotifier {
  final SettingsService _settingsService = SettingsService();

  GlassMode _mode = GlassMode.disabled;
  double _lightAngle = 62.0;
  double _blur = 8.0;

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

  /// Угол освещения (в градусах, 0°..360°)
  double get lightAngle => _lightAngle;

  /// Для обратной совместимости
  double get manualLightAngle => _lightAngle;

  /// Степень размытия заднего плана (blur sigma)
  double get blur => _blur;

  /// Эффект размытия заднего плана для передачи в LiquidGlassLens
  LiquidGlassBlur get blurEffect => LiquidGlassBlur(sigmaX: _blur, sigmaY: _blur);

  /// Вычисляет итоговый угол освещения для передачи в шейдеры/виджеты.
  /// Стабилен и не вызывает ненужных перерисовок.
  double getEffectiveLightAngle({bool reduceMotion = false}) {
    if (reduceMotion) {
      return 62.0;
    }
    return _lightAngle;
  }

  /// Инициализация из SettingsService
  void init() {
    _mode = _settingsService.glassMode;
    // Если платформа не поддерживается, принудительно сбрасываем
    if (!isSupported && _mode != GlassMode.disabled) {
      _mode = GlassMode.disabled;
      _settingsService.saveGlassMode(GlassMode.disabled);
    }
    _lightAngle = _settingsService.manualLightAngle;
    _blur = _settingsService.glassBlur;
    notifyListeners();
  }

  /// Установить режим Liquid Glass дизайна
  Future<void> setMode(GlassMode value) async {
    if (!isSupported) return; // Запрещаем включение на неподдерживаемых платформах
    if (_mode == value) return;
    _mode = value;
    await _settingsService.saveGlassMode(value);
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

  /// Задать угол освещения (0°..360°)
  Future<void> setManualLightAngle(double angle) async {
    final clamped = angle.clamp(0.0, 360.0);
    if (_lightAngle == clamped) return;
    _lightAngle = clamped;
    await _settingsService.saveManualLightAngle(clamped);
    notifyListeners();
  }

  /// Задать степень размытия стекла (0..30)
  Future<void> setBlur(double blur) async {
    final clamped = blur.clamp(0.0, 30.0);
    if (_blur == clamped) return;
    _blur = clamped;
    await _settingsService.saveGlassBlur(clamped);
    notifyListeners();
  }
}
