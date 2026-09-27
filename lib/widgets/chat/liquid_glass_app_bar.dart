import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart' hide LiquidGlassAppBar;

/// AppBar с Liquid Glass эффектом и затемнением.
///
/// Используется как `Positioned` виджет в Stack когда Liquid Glass дизайн
/// включён. Glass-панель преломляет контент позади (сообщения),
/// с лёгким затемнением для лучшей читаемости.
///
/// Содержимое AppBar (заголовок, действия) отображается поверх
/// glass-эффекта. Поддерживает необязательный [bottom] виджет (TabBar).
class LiquidGlassAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  /// Виджет заголовка (обычно Row с аватаром и именем)
  final Widget title;

  /// Действия справа (кнопки звонка, меню и т.д.)
  final List<Widget>? actions;

  /// Кнопка «назад»
  final Widget? leading;

  /// Нижний виджет (например, TabBar)
  final PreferredSizeWidget? bottom;

  /// Центрировать ли заголовок по всей ширине AppBar (а не только
  /// в пространстве между leading и actions)
  final bool centerTitle;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Динамический угол освещения бликов (в градусах)
  final double? lightAngle;

  const LiquidGlassAppBar({
    Key? key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.centerTitle = false,
    this.isLite = false,
    this.lightAngle,
  }) : super(key: key);

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final statusBarHeight = MediaQuery.of(context).padding.top;
    final bottomHeight = bottom?.preferredSize.height ?? 0;
    final totalHeight = kToolbarHeight + statusBarHeight + bottomHeight;

    final barStyle = LiquidGlassStyle(
      shape: LiquidGlassShape.roundedRectangle(
        cornerRadius: 0,
        borderWidth: 0,
        lightDirection: lightAngle ?? 62.0,
      ),
      appearance: LiquidGlassAppearance(
        color: isDark
            ? const Color.fromARGB(80, 20, 20, 30)
            : const Color.fromARGB(80, 200, 200, 210),
        blur: const LiquidGlassBlur(sigmaX: 12, sigmaY: 12),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.05,
        distortionWidth: 20,
      ),
      liteGlass: isLite ? LiquidGlassLitePickup.surface : null,
    );

    // Делаем статус-бар прозрачным чтобы glass-эффект AppBar
    // распространялся на область статус-бара без цветового разрыва
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: SizedBox(
        height: totalHeight,
        width: double.infinity,
        child: LiquidGlassLens(
          style: barStyle,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Содержимое AppBar поверх glass
                Positioned(
                  left: 0,
                  right: 0,
                  top: statusBarHeight,
                  height: kToolbarHeight,
                  child: centerTitle
                      // Истинное центрирование: title по центру всего
                      // экрана, leading/actions поверх него
                      ? Stack(
                          children: [
                            Center(child: title),
                            Row(
                              children: [
                                if (leading != null)
                                  leading!
                                else
                                  IconButton(
                                    icon: iconoir.NavArrowLeft(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      width: 24,
                                      height: 24,
                                    ),
                                    onPressed: () => Navigator.maybePop(context),
                                  ),
                                const Spacer(),
                                if (actions != null) ...actions!,
                              ],
                            ),
                          ],
                        )
                      // Обычная раскладка: title между leading и actions
                      : Row(
                          children: [
                            if (leading != null)
                              leading!
                            else
                              IconButton(
                                icon: iconoir.NavArrowLeft(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  width: 24,
                                  height: 24,
                                ),
                                onPressed: () => Navigator.maybePop(context),
                              ),
                            Expanded(child: title),
                            if (actions != null) ...actions!,
                          ],
                        ),
                ),
                // Bottom widget (TabBar) если есть
                if (bottom != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: statusBarHeight + kToolbarHeight,
                    child: bottom!,
                  ),
                // Тонкая тёмная линия снизу для читаемости в светлой теме
                if (!isDark)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 0.5,
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
              ],
            ),
          ),
        ),
    );
  }
}
