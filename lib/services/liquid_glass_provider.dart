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
  GlassMode get mode => _mode;

  /// Включён ли какой-либо стеклянный дизайн (lite или full).
  bool get enabled => _mode != GlassMode.disabled;

  /// Включён ли облегчённый режим (FakeGlass).
  bool get isLite => _mode == GlassMode.lite;

  /// Включён ли полный режим (LiquidGlass).
  bool get isFull => _mode == GlassMode.full;

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
    LiquidGlassClipQuality clipQuality = LiquidGlassClipQuality.roundedRectangle,
    LiquidGlassShape? shape,
    Color? color,
    double? blur,
    LiquidGlassShadow? shadow,
    double refractionIndex = 1.1,
    double refractionWidth = 24.0,
    double dispersion = 0.0,
    double saturation = 1.2,
    double borderWidth = 1.25,
    Color? borderColor,
    bool includeGlow = false,
    bool? isLiteOverride,
    bool? isDarkOverride,
    LiquidGlassAdaptivity? adaptivity,
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
        : const Color(0x66FFFFFF);

    final effectiveShape = shape ??
        LiquidGlassShape(
          cornerRadius: cornerRadius,
          cornerStyle: cornerStyle,
          clipQuality: clipQuality,
        );

    // Адаптивная окантовка (specular):
    // - На тёмной теме: borderColor ?? null (при null шейдер автоматически берёт
    //   цвет фона под гранью и высветляет его через rimLift, создавая естественный блик)
    // - На светлой теме: borderColor ?? const Color(0xCC2C2C2E) (тёмно-графитовая окантовка,
    //   устраняющая белый ореол и формирующая тёмный оптический контур)
    final effectiveBorderColor =
        borderColor ?? (isDark ? null : const Color(0xCC2C2C2E));

    final specular = borderWidth > 0
        ? LiquidGlassLight.specular(
            thickness: borderWidth * 4.0,
            sharpness: 0.5,
            angle: angle,
            spread: 0.9,
            intensity: isDark ? 1.0 : 0.75,
            oppositeIntensity: 1.0,
            color: effectiveBorderColor,
          )
        : const LiquidGlassLight.specular(thickness: 0);

    final glow = (borderWidth > 0 && includeGlow)
        ? LiquidGlassLight.glow(
            thickness: borderWidth * 8.0,
            angle: angle + 90,
            spread: 0.5,
            intensity: isDark ? 0.3 : 0.2,
            color: effectiveBorderColor,
          )
        : null;

    return LiquidGlassStyle(
      shape: effectiveShape,
      color: color ?? defaultColor,
      blur: blur ?? _blur,
      shadow: shadow,
      specular: specular,
      glow: glow,
      refractionIndex: refractionIndex,
      refractionWidth: refractionWidth,
      dispersion: dispersion,
      saturation: saturation,
      adaptivity: adaptivity,
      liteGlass: lite,
    );
  }

  /// Инициализация из SettingsService
  void init() {
    _mode = _settingsService.glassMode;
    _lightAngle = _settingsService.manualLightAngle;
    _blur = _settingsService.glassBlur;
    notifyListeners();
  }

  /// Установить режим Liquid Glass дизайна
  Future<void> setMode(GlassMode value) async {
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
