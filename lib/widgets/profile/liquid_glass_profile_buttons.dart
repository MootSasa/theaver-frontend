import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../services/liquid_glass_provider.dart';

/// Описание отдельной кнопки действия для профиля.
class ProfileActionButtonItem {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDestructive;
  final String? label;

  const ProfileActionButtonItem({
    required this.icon,
    this.onTap,
    this.isDestructive = false,
    this.label,
  });
}

/// Круглые кнопки действий под именем пользователя:
/// «Выбрать фото», «QR-код», «Изменить», «Удалить фото»
/// или кастомный список кнопок для профилей других пользователей.
///
/// Отображаются исключительно иконки в увеличенных круглых кнопках (без текста).
/// В режиме liquid glass используется эффект `LiquidStretch` и повышенная прозрачность.
/// В обычном дизайне стретч отключён.
class LiquidGlassProfileButtons extends StatelessWidget {
  /// Включён ли стеклянный дизайн (полный или облегчённый)
  final bool enabled;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Кастомный список кнопок действий (например, для собеседника: чат, звонок, видео, заглушить)
  final List<ProfileActionButtonItem>? customButtons;

  /// Коллбэк при нажатии «Выбрать фото»
  final VoidCallback? onChoosePhoto;

  /// Коллбэк при нажатии «QR-код»
  final VoidCallback? onQrCode;

  /// Коллбэк при нажатии «Изменить»
  final VoidCallback? onEdit;

  /// Коллбэк при нажатии «Удалить фото»
  final VoidCallback? onDeletePhoto;

  /// Есть ли аватарка (для отображения кнопки удаления)
  final bool hasAvatar;

  /// Относительный прогресс сворачивания шапки (0.0 = полностью видны, 1.0 = исчезли)
  final double collapseProgress;

  /// Опциональные подписи (для обратной совместимости)
  final String choosePhotoLabel;
  final String qrCodeLabel;
  final String editLabel;
  final String deletePhotoLabel;

  const LiquidGlassProfileButtons({
    Key? key,
    required this.enabled,
    this.isLite = false,
    this.customButtons,
    this.onChoosePhoto,
    this.onQrCode,
    this.onEdit,
    this.onDeletePhoto,
    this.hasAvatar = false,
    this.collapseProgress = 0.0,
    this.choosePhotoLabel = 'Выбрать фото',
    this.qrCodeLabel = 'QR-код',
    this.editLabel = 'Изменить',
    this.deletePhotoLabel = 'Удалить',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final progress = collapseProgress.clamp(0.0, 1.0);
    // Быстрое затухание (к прогрессу 0.65 уже полностью прозрачны, не касаясь краёв)
    final opacity = (1.0 - progress * 1.6).clamp(0.0, 1.0);
    final scale = (1.0 - progress * 0.35).clamp(0.0, 1.0);
    final leftOffset = -progress * 35.0;
    final rightOffset = progress * 35.0;

    if (opacity <= 0.001) {
      return const SizedBox(height: 58.0);
    }

    return IgnorePointer(
      ignoring: opacity < 0.5,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: customButtons != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < customButtons!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Transform.translate(
                        offset: Offset(
                          (i - (customButtons!.length - 1) / 2.0) * progress * 24.0,
                          0,
                        ),
                        child: _RoundActionButton(
                          icon: customButtons![i].icon,
                          isDark: isDark,
                          enabled: enabled,
                          isLite: isLite,
                          onTap: customButtons![i].onTap,
                          isDestructive: customButtons![i].isDestructive,
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(leftOffset, 0),
                      child: _RoundActionButton(
                        icon: Icons.photo_camera_rounded,
                        isDark: isDark,
                        enabled: enabled,
                        isLite: isLite,
                        onTap: onChoosePhoto,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Transform.translate(
                      offset: Offset(leftOffset * 0.4, 0),
                      child: _RoundActionButton(
                        icon: Icons.qr_code_rounded,
                        isDark: isDark,
                        enabled: enabled,
                        isLite: isLite,
                        onTap: onQrCode,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Transform.translate(
                      offset: Offset(rightOffset * 0.4, 0),
                      child: _RoundActionButton(
                        icon: Icons.edit_rounded,
                        isDark: isDark,
                        enabled: enabled,
                        isLite: isLite,
                        onTap: onEdit,
                      ),
                    ),
                    if (hasAvatar) ...[
                      const SizedBox(width: 14),
                      Transform.translate(
                        offset: Offset(rightOffset, 0),
                        child: _RoundActionButton(
                          icon: Icons.delete_outline_rounded,
                          isDark: isDark,
                          enabled: enabled,
                          isLite: isLite,
                          onTap: onDeletePhoto,
                          isDestructive: true,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Увеличенная круглая кнопка действия без текста и без всплывающих подсказок.
class _RoundActionButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final bool enabled;
  final bool isLite;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _RoundActionButton({
    required this.icon,
    required this.isDark,
    required this.enabled,
    this.isLite = false,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isDestructive
        ? Colors.red.shade400
        : (isDark ? Colors.white70 : const Color(0xFF0088CC));

    // Увеличенный диаметр кнопок действий (58.0)
    const size = 58.0;

    Widget buttonContent;

    if (enabled) {
      final glassProvider = context.watch<LiquidGlassProvider>();
      final glassStyle = glassProvider.createStyle(
        context: context,
        isLiteOverride: isLite,
        shape: const LiquidGlassShape.roundedRectangle(
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
        child: Icon(icon, size: 24, color: iconColor),
      );

      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlassLens(
          style: glassStyle,
          child: buttonChild,
        ),
      );
    } else {
      // Modern круглый дизайн без стекла (без LiquidStretch)
      final cardColor = isDark
          ? const Color.fromARGB(180, 44, 44, 46)
          : const Color.fromARGB(220, 255, 255, 255);

      buttonContent = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cardColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 24, color: iconColor),
      );

      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: buttonContent,
      );
    }
  }
}
