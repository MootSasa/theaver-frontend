import 'package:flutter/material.dart';

/// Стиль полоски цитирования/ответа в стиле Telegram
enum ReplyStripStyle {
  /// Одноцветная классическая линия
  solid,

  /// Двухцветный градиент/сплит
  dualColor,

  /// Трёхцветная диагональная полоса ("карамельная палочка")
  candyCane,

  /// Пунктирная/сегментированная линия
  segmented,
}

/// Модель пресета цвета имени и полоски ответа
class NameColorPreset {
  final String id;
  final String nameKey;
  final Color primaryColor;
  final Color? secondaryColor;
  final Color? tertiaryColor;

  const NameColorPreset({
    required this.id,
    required this.nameKey,
    required this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
  });

  Color get effectiveSecondary => secondaryColor ?? primaryColor;
  Color get effectiveTertiary => tertiaryColor ?? secondaryColor ?? primaryColor;

  /// Возвращает 100% непрозрачный яркий фон для карточек цитирования/ответов,
  /// одинаковый как в светлой, так и в тёмной теме.
  Color getOpaqueCardBackgroundColor([bool? isDark]) {
    final hsl = HSLColor.fromColor(primaryColor.withValues(alpha: 1.0));
    final double sat = (hsl.saturation * 0.85).clamp(0.50, 0.90);
    return hsl
        .withLightness(0.83)
        .withSaturation(sat)
        .toColor();
  }

  static double _contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final bright = l1 > l2 ? l1 : l2;
    final dark = l1 > l2 ? l2 : l1;
    return (bright + 0.05) / (dark + 0.05);
  }

  /// Подбирает контрастный читаемый цвет текста для подложки [bgColor].
  /// Если [configuredColor] задан явно пользователем и имеет достаточный контраст (>= 3.2),
  /// используется он; иначе выбирается тёмный или светлый цвет в зависимости от яркости [bgColor].
  static Color resolveReadableTextColor(
    Color bgColor, {
    Color? configuredColor,
    bool isExplicitCustom = false,
  }) {
    final bool isLightBg = bgColor.computeLuminance() > 0.42;
    if (isExplicitCustom && configuredColor != null) {
      if (_contrastRatio(bgColor, configuredColor) >= 3.2) {
        return configuredColor;
      }
    }
    return isLightBg ? const Color(0xFF1C2530) : const Color(0xFFF1F5F9);
  }

  /// Подбирает контрастный акцентный цвет (имя отправителя, иконка, ссылка) на фоне [bgColor].
  static Color resolveReadableAccentColor(Color bgColor, Color accentColor) {
    if (_contrastRatio(bgColor, accentColor) >= 2.6) {
      return accentColor;
    }
    final bool isLightBg = bgColor.computeLuminance() > 0.42;
    final hsl = HSLColor.fromColor(accentColor.withValues(alpha: 1.0));
    if (isLightBg) {
      return hsl
          .withLightness(hsl.lightness.clamp(0.18, 0.36))
          .withSaturation(hsl.saturation.clamp(0.55, 0.95))
          .toColor();
    } else {
      return hsl
          .withLightness(hsl.lightness.clamp(0.68, 0.85))
          .withSaturation(hsl.saturation.clamp(0.55, 0.95))
          .toColor();
    }
  }

  factory NameColorPreset.fromCustomColor(Color color) {
    final opaque = color.withValues(alpha: 1.0);
    final hsl = HSLColor.fromColor(opaque);
    final sec = hsl.withHue((hsl.hue + 35) % 360).toColor();
    final tert = hsl.withHue((hsl.hue + 70) % 360).toColor();
    return NameColorPreset(
      id: 'custom_name_${opaque.toARGB32()}',
      nameKey: 'name_color_custom',
      primaryColor: opaque,
      secondaryColor: sec,
      tertiaryColor: tert,
    );
  }

  factory NameColorPreset.fromCustomGradient(Color color1, Color color2) {
    final c1 = color1.withValues(alpha: 1.0);
    final c2 = color2.withValues(alpha: 1.0);
    final hsl = HSLColor.fromColor(c1);
    final c3 = hsl.withHue((hsl.hue + 60) % 360).toColor();
    return NameColorPreset(
      id: 'custom_name_dual_${c1.toARGB32()}_${c2.toARGB32()}',
      nameKey: 'name_color_custom',
      primaryColor: c1,
      secondaryColor: c2,
      tertiaryColor: c3,
    );
  }

  factory NameColorPreset.fromCustomTriple(Color color1, Color color2, Color color3) {
    final c1 = color1.withValues(alpha: 1.0);
    final c2 = color2.withValues(alpha: 1.0);
    final c3 = color3.withValues(alpha: 1.0);
    return NameColorPreset(
      id: 'custom_name_triple_${c1.toARGB32()}_${c2.toARGB32()}_${c3.toARGB32()}',
      nameKey: 'name_color_custom',
      primaryColor: c1,
      secondaryColor: c2,
      tertiaryColor: c3,
    );
  }
}

/// Набор классических пресетов цвета имени Telegram
class NameColorPresets {
  static const red = NameColorPreset(
    id: 'name_red',
    nameKey: 'name_color_red',
    primaryColor: Color(0xFFE53935),
    secondaryColor: Color(0xFFFF7043),
    tertiaryColor: Color(0xFFFFB74D),
  );

  static const orange = NameColorPreset(
    id: 'name_orange',
    nameKey: 'name_color_orange',
    primaryColor: Color(0xFFFB8C00),
    secondaryColor: Color(0xFFFFB300),
    tertiaryColor: Color(0xFF81C784),
  );

  static const violet = NameColorPreset(
    id: 'name_violet',
    nameKey: 'name_color_violet',
    primaryColor: Color(0xFF8E24AA),
    secondaryColor: Color(0xFFBA68C8),
    tertiaryColor: Color(0xFF4DD0E1),
  );

  static const green = NameColorPreset(
    id: 'name_green',
    nameKey: 'name_color_green',
    primaryColor: Color(0xFF43A047),
    secondaryColor: Color(0xFF7CB342),
    tertiaryColor: Color(0xFFFFD54F),
  );

  static const cyan = NameColorPreset(
    id: 'name_cyan',
    nameKey: 'name_color_cyan',
    primaryColor: Color(0xFF00ACC1),
    secondaryColor: Color(0xFF26A69A),
    tertiaryColor: Color(0xFF80CBC4),
  );

  static const blue = NameColorPreset(
    id: 'name_blue',
    nameKey: 'name_color_blue',
    primaryColor: Color(0xFF1E88E5),
    secondaryColor: Color(0xFF42A5F5),
    tertiaryColor: Color(0xFF26C6DA),
  );

  static const pink = NameColorPreset(
    id: 'name_pink',
    nameKey: 'name_color_pink',
    primaryColor: Color(0xFFD81B60),
    secondaryColor: Color(0xFFEC407A),
    tertiaryColor: Color(0xFFAB47BC),
  );

  static const List<NameColorPreset> defaults = [
    red,
    orange,
    violet,
    green,
    cyan,
    blue,
    pink,
  ];

  static NameColorPreset getById(String id) {
    if (id.startsWith('custom_name_triple_')) {
      final parts = id.replaceFirst('custom_name_triple_', '').split('_');
      if (parts.length == 3) {
        final v1 = int.tryParse(parts[0]);
        final v2 = int.tryParse(parts[1]);
        final v3 = int.tryParse(parts[2]);
        if (v1 != null && v2 != null && v3 != null) {
          return NameColorPreset.fromCustomTriple(Color(v1), Color(v2), Color(v3));
        }
      }
    } else if (id.startsWith('custom_name_dual_')) {
      final parts = id.replaceFirst('custom_name_dual_', '').split('_');
      if (parts.length == 2) {
        final v1 = int.tryParse(parts[0]);
        final v2 = int.tryParse(parts[1]);
        if (v1 != null && v2 != null) {
          return NameColorPreset.fromCustomGradient(Color(v1), Color(v2));
        }
      }
    } else if (id.startsWith('custom_name_')) {
      final valStr = id.replaceFirst('custom_name_', '');
      final val = int.tryParse(valStr);
      if (val != null) {
        return NameColorPreset.fromCustomColor(Color(val));
      }
    }
    return defaults.firstWhere(
      (p) => p.id == id,
      orElse: () => red,
    );
  }
}
