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

  /// Степень размытия заднего плана (blur sigma) для передачи в LiquidGlassLens
  double get blurEffect => _blur;

  /// Вычисляет итоговый угол освещения для передачи в шейдеры/виджеты.
  /// Стабилен и не вызывает ненужных перерисовок.
  double getEffectiveLightAngle({bool reduceMotion = false}) {
    if (reduceMotion) {
      return 62.0;
    }
    return _lightAngle;
  }

  /// Создает унифицированный [LiquidGlassStyle] для приложения Miptgram,
  /// адаптированный под текущую тему, угол освещения и режим (full/lite).
  LiquidGlassStyle createStyle({
    BuildContext? context,
    double cornerRadius = 0,
    LiquidGlassCornerStyle cornerStyle = LiquidGlassCornerStyle.continuousRoundedRectangle,
    LiquidGlassClipQuality clipQuality = LiquidGlassClipQuality.exact,
    LiquidGlassShape? shape,
    Color? color,
    double? blur,
    LiquidGlassShadow? shadow,
    double refractionIndex = 1.02,
    double refractionWidth = 12.0,
    double borderWidth = 0.35,
    bool includeGlow = false,
    bool? isLiteOverride,
    bool? isDarkOverride,
  }) {
    final isDark = isDarkOverride ??
        (context != null
            ? Theme.of(context).brightness == Brightness.dark
            : true);
    final reduceMotion =
        context != null ? MediaQuery.disableAnimationsOf(context) : false;
    final angle = getEffectiveLightAngle(reduceMotion: reduceMotion);
    final lite = isLiteOverride ?? isLite;

    final defaultColor = isDark
        ? const Color(0x33202025)
        : const Color(0x8FFFFFFF);

    final effectiveShape = shape ??
        LiquidGlassShape(
          cornerRadius: cornerRadius,
          cornerStyle: cornerStyle,
          clipQuality: clipQuality,
        );

    final specular = borderWidth > 0
        ? LiquidGlassLight.specular(
            thickness: borderWidth * 3.0,
            sharpness: 0.98,
            angle: angle,
            intensity: isDark ? 0.6 : 0.85,
          )
        : null;

    final glow = (borderWidth > 0 && includeGlow)
        ? LiquidGlassLight.glow(
            thickness: borderWidth * 8.0,
            angle: angle + 90,
            intensity: 0.3,
          )
        : null;

    return LiquidGlassStyle(
      shape: effectiveShape,
      color: color ?? defaultColor,
      blur: blur ?? _blur,
      shadow: null,
      specular: specular,
      glow: glow,
      refractionIndex: refractionIndex,
      refractionWidth: refractionWidth,
      liteGlass: lite,
    );
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
