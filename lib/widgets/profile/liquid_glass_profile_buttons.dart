import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../services/liquid_glass_provider.dart';

/// Описание отдельной круглой кнопки быстрого действия для профиля.
/// Поддерживает иконки `iconoir_flutter` через [iconBuilder] (приоритетно)
/// и опциональный [icon] для обратной совместимости.
class ProfileActionButtonItem {
  final Widget Function(Color color, double size)? iconBuilder;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isDestructive;
  final String? label;

  const ProfileActionButtonItem({
    this.iconBuilder,
    this.icon,
    this.onTap,
    this.isDestructive = false,
    this.label,
  }) : assert(iconBuilder != null || icon != null, 'Either iconBuilder or icon must be provided');
}

/// Круглые кнопки быстрых действий под именем и статусом профиля (только иконки, от 3 до 5 кнопок).
///
/// Все иконки отрисовываются через `iconoir_flutter`.
/// При количестве кнопок 5 диаметр и отступы автоматически адаптируются под ширину экрана.
class LiquidGlassProfileButtons extends StatelessWidget {
  /// Включён ли стеклянный дизайн (полный или облегчённый)
  final bool enabled;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Кастомный список кнопок действий (от 3 до 5 кнопок в зависимости от типа профиля и прав)
  final List<ProfileActionButtonItem>? customButtons;

  /// Коллбэк при нажатии «Выбрать фото» (для своего профиля)
  final VoidCallback? onChoosePhoto;

  /// Коллбэк при нажатии «QR-код» (опционально)
  final VoidCallback? onQrCode;

  /// Коллбэк при нажатии «Изменить» (для своего профиля)
  final VoidCallback? onEdit;

  /// Коллбэк при нажатии «Цвет профиля» (для своего профиля)
  final VoidCallback? onChangeColor;

  /// Коллбэк при нажатии «Удалить фото» (опционально)
  final VoidCallback? onDeletePhoto;

  /// Есть ли аватарка
  final bool hasAvatar;

  /// Активен ли цветной/градиентный пресет профиля (всегда светлые иконки и единое стекло)
  final bool hasColoredTheme;

  /// Относительный прогресс сворачивания шапки (0.0 = полностью видны, 1.0 = свернулись и улетели за аватаркой)
  final double collapseProgress;

  /// Дополнительная дистанция вертикального улёта вслед за круглой аватаркой (в логических пикселях)
  final double extraFlyUpDistance;

  /// Опциональные подписи (для обратной совместимости)
  final String choosePhotoLabel;
  final String qrCodeLabel;
  final String editLabel;
  final String deletePhotoLabel;

  const LiquidGlassProfileButtons({
    Key? key,
    required this.enabled,
    this.isLite = false,
    this.hasColoredTheme = false,
    this.customButtons,
    this.onChoosePhoto,
    this.onQrCode,
    this.onEdit,
    this.onChangeColor,
    this.onDeletePhoto,
    this.hasAvatar = false,
    this.collapseProgress = 0.0,
    this.extraFlyUpDistance = 126.0,
    this.choosePhotoLabel = 'Выбрать фото',
    this.qrCodeLabel = 'QR-код',
    this.editLabel = 'Изменить',
    this.deletePhotoLabel = 'Удалить',
  }) : super(key: key);

  List<ProfileActionButtonItem> _resolveButtons() {
    if (customButtons != null && customButtons!.isNotEmpty) {
      return customButtons!;
    }
    // По умолчанию для своего профиля: 3 кнопки (Камера, Изменить, Палитра темы)
    return [
      ProfileActionButtonItem(
        iconBuilder: (color, size) => iconoir.Camera(
          color: color,
          width: size,
          height: size,
        ),
        onTap: onChoosePhoto,
        label: choosePhotoLabel,
      ),
      ProfileActionButtonItem(
        iconBuilder: (color, size) => iconoir.EditPencil(
          color: color,
          width: size,
          height: size,
        ),
        onTap: onEdit,
        label: editLabel,
      ),
      ProfileActionButtonItem(
        iconBuilder: (color, size) => iconoir.Palette(
          color: color,
          width: size,
          height: size,
        ),
        onTap: onChangeColor ?? onQrCode,
        label: qrCodeLabel,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final progress = collapseProgress.clamp(0.0, 1.0);
    if (progress >= 0.999) {
      return const SizedBox(height: 58.0);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark || hasColoredTheme;

    final buttons = _resolveButtons();
    final count = buttons.length;
    if (count == 0) {
      return const SizedBox(height: 58.0);
    }

    // Меняем прозрачность ТОЛЬКО у значков внутри кнопок; сами кнопки всегда имеют непрозрачность 1.0
    final double iconOpacity = (1.0 - (progress / 0.42)).clamp(0.0, 1.0);

    // Фаза схождения всех кнопок в одну по центру (0.0 → 0.62)
    final double coalesceRaw = (progress / 0.62).clamp(0.0, 1.0);
    final double coalesceT = Curves.easeInOutCubic.transform(coalesceRaw);

    // Плавное поглощение боковых капель внутри центральной, чтобы итоговая единая кнопка
    // имела ровно диаметр одной кнопки без раздувания метаболл-поля
    final double absorbT = Curves.easeInOutCubic.transform(
      ((coalesceT - 0.35) / 0.65).clamp(0.0, 1.0),
    );

    // Вертикальный улёт/выплывание вслед за круглой аватаркой
    final double flyT = Curves.easeInCubic.transform(
      ((progress - 0.12) / 0.88).clamp(0.0, 1.0),
    );
    final double extraDy = -flyT * extraFlyUpDistance;

    // Небольшое сужение единой капли на финальном участке ухода за верхний край экрана
    final double flightScale = 1.0 -
        0.40 *
            Curves.easeInQuad.transform(
              ((progress - 0.45) / 0.55).clamp(0.0, 1.0),
            );

    // Радиус жидкостного слияния (liquid blend):
    // 0 в полном покое (чтобы кнопки в ряду не склеивались), до 28px при слиянии/разделении
    final double blendRampIn =
        Curves.easeOutCubic.transform((progress / 0.10).clamp(0.0, 1.0));
    final double blendSettle = 1.0 -
        0.42 *
            Curves.easeInCubic.transform(
              ((progress - 0.52) / 0.48).clamp(0.0, 1.0),
            );
    final double smoothness =
        progress <= 0.004 ? 0.0 : (28.0 * blendRampIn * blendSettle);

    return IgnorePointer(
      ignoring: progress > 0.25,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width - 32.0;
          final spacing = count >= 5 ? 10.0 : 14.0;
          final rawSize = (availWidth - (count - 1) * spacing) / count;
          final btnSize = math.min(58.0, math.max(44.0, rawSize));
          final baseCurrentSize = btnSize * flightScale;
          final int primaryIndex = count ~/ 2;

          // Запас вокруг кнопок внутри LiquidGlassBlender, чтобы внутренний _glassClipRect
          // никогда не подрезал метаболл-перешейки и бликовую грань
          const double hPad = 20.0;
          const double vPad = 24.0;
          final double blenderWidth = availWidth + hPad * 2;
          final double blenderHeight = btnSize + vPad * 2;
          final double centerX = blenderWidth / 2.0;
          final double centerY = blenderHeight / 2.0;

          final List<Widget> positionedButtons = <Widget>[];
          for (int i = 0; i < count; i++) {
            final bool isPrimary = i == primaryIndex;
            final double restDx =
                (i - (count - 1) / 2.0) * (btnSize + spacing);
            final double dx = restDx * (1.0 - coalesceT);

            final double shrinkAmount =
                isPrimary ? 0.0 : (2.15 * smoothness + 16.0) * absorbT;
            final double itemSize = math.max(
              isPrimary ? 18.0 : 10.0,
              baseCurrentSize - shrinkAmount,
            );

            // В обычном (не-стеклянном) режиме скрываем боковые кнопки, когда они уже
            // полностью вошли внутрь центральной, чтобы полупрозрачный цвет не наслаивался
            if (!enabled && !isPrimary && coalesceT >= 0.92) {
              continue;
            }

            positionedButtons.add(
              Positioned(
                left: centerX + dx - itemSize / 2.0,
                top: centerY - itemSize / 2.0,
                width: itemSize,
                height: itemSize,
                child: _RoundActionButton(
                  item: buttons[i],
                  size: itemSize,
                  restSize: btnSize,
                  iconOpacity: iconOpacity,
                  isDark: isDark,
                  enabled: enabled,
                  isLite: isLite,
                ),
              ),
            );
          }

          Widget surface = SizedBox(
            width: blenderWidth,
            height: blenderHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: positionedButtons,
            ),
          );

          if (enabled && count >= 2) {
            final glassProvider = context.watch<LiquidGlassProvider>();
            final blenderStyle = glassProvider.createStyle(
              context: context,
              isDarkOverride: isDark,
              isLiteOverride: isLite,
              color:
                  isDark ? const Color(0x33202025) : const Color(0x66FFFFFF),
              refractionIndex: 1.15,
              refractionWidth: 22.0,
              shape: LiquidGlassShape.roundedRectangle(
                cornerRadius: baseCurrentSize / 2,
              ),
            );

            surface = LiquidGlassBlender(
              style: blenderStyle,
              smoothness: smoothness,
              child: surface,
            );
          }

          return SizedBox(
            width: availWidth,
            height: 58.0,
            child: Transform.translate(
              offset: Offset(0, extraDy),
              child: OverflowBox(
                minWidth: blenderWidth,
                maxWidth: blenderWidth,
                minHeight: blenderHeight,
                maxHeight: blenderHeight,
                child: surface,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Круглая кнопка быстрого действия (только иконка `iconoir`, без текста).
class _RoundActionButton extends StatelessWidget {
  final ProfileActionButtonItem item;
  final double size;
  final double restSize;
  final double iconOpacity;
  final bool isDark;
  final bool enabled;
  final bool isLite;

  const _RoundActionButton({
    required this.item,
    required this.size,
    required this.restSize,
    required this.iconOpacity,
    required this.isDark,
    required this.enabled,
    this.isLite = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = item.isDestructive
        ? Colors.red.shade400
        : (isDark
            ? Colors.white.withValues(alpha: 0.92)
            : const Color(0xFF1C1C1E));
    final iconSize = (restSize * 0.42).clamp(20.0, 24.0);

    Widget iconChild;
    if (iconOpacity <= 0.001) {
      iconChild = const SizedBox.shrink();
    } else {
      final Widget rawIcon = item.iconBuilder != null
          ? item.iconBuilder!(iconColor, iconSize)
          : Icon(item.icon, size: iconSize, color: iconColor);
      iconChild = Opacity(
        opacity: iconOpacity,
        child: rawIcon,
      );
    }

    if (enabled) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final glassStyle = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDark,
        isLiteOverride: isLite,
        color: isDark ? const Color(0x33202025) : const Color(0x66FFFFFF),
        refractionIndex: 1.15,
        refractionWidth: 22.0,
        shape: LiquidGlassShape.roundedRectangle(
          cornerRadius: size / 2,
        ),
      );

      final buttonChild = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: isDark
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
        child: iconChild,
      );

      return GestureDetector(
        onTap: item.onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlassLens(
          style: glassStyle,
          child: buttonChild,
        ),
      );
    } else {
      final cardColor = isDark
          ? const Color(0x992C2C2E)
          : const Color(0xB3FFFFFF);

      return GestureDetector(
        onTap: item.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cardColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: iconChild,
              ),
            ),
          ),
        ),
      );
    }
  }
}
