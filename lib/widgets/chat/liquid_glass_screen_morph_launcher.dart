import 'dart:async';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../utils/swipe_back_route.dart';
import '../../utils/haptic_utils.dart';

/// Кастомный маршрут для бесшовного перехода из жидкого морфинга (Seamless Hand-off).
///
/// **Push**: 0ms длительность — страница появляется мгновенно, без дополнительного слайда,
///           подхватывая финальное состояние раскрытого LiquidGlassMorph.
/// **Pop / Свайп назад**: 250ms стандартная интерактивная анимация [SwipeBackPageRoute],
///                       возвращающая пользователя в чат.
class HandOffSwipeBackPageRoute<T> extends SwipeBackPageRoute<T> {
  HandOffSwipeBackPageRoute({
    required super.builder,
    super.settings,
  });

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animation.status == AnimationStatus.reverse || popGestureInProgress) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return child;
  }
}

/// Виджет-лаунчер для плавного перетекания стеклянного элемента интерфейса
/// (например, верхней плашки в шапке чата) в полноценный экран.
///
/// **Архитектурный принцип**:
/// 1. В покое отображает [child] в своем обычном месте в дереве.
/// 2. При тапе замеряет глобальный [Rect] и через [OverlayPortal] запускает [LiquidGlassMorph],
///    растекающийся из исходного положения на весь экран.
/// 3. По завершении анимации ([LiquidGlassMorph.onEnd]) бесшовно передает управление
///    настоящему [Route] через [destinationBuilder].
/// 4. При возврате из экрана ([Navigator.pop]) оверлей очищается, и шапка чата готова к работе.
class LiquidGlassScreenMorphLauncher extends StatefulWidget {
  /// Исходный свернутый виджет (например, содержимое центральной плашки шапки).
  final Widget child;

  /// Билдер для построения целевого полноценного экрана (не стекло!).
  final WidgetBuilder destinationBuilder;

  /// Опциональный билдер для превью внутри морфа во время полета.
  /// Если null — используется полупрозрачная адаптивная заглушка с цветом темы.
  final WidgetBuilder? expandedPreviewBuilder;

  /// Включен ли эффект жидкого стекла (при false переход происходит через обычный push).
  final bool enabled;

  /// Стиль стекла для морфинга.
  final LiquidGlassStyle style;

  /// Пресет кинематики морфинга (по умолчанию [LiquidGlassMorphMotion.fluid]).
  final LiquidGlassMorphMotion motion;

  /// Плавность перешейка капель (smoothness).
  final double smoothness;

  /// Опциональный колбэк перед началом перехода.
  final VoidCallback? onTap;

  const LiquidGlassScreenMorphLauncher({
    super.key,
    required this.child,
    required this.destinationBuilder,
    this.expandedPreviewBuilder,
    this.enabled = true,
    required this.style,
    this.motion = LiquidGlassMorphMotion.fluid,
    this.smoothness = 45.0,
    this.onTap,
  });

  @override
  State<LiquidGlassScreenMorphLauncher> createState() =>
      _LiquidGlassScreenMorphLauncherState();
}

class _LiquidGlassScreenMorphLauncherState
    extends State<LiquidGlassScreenMorphLauncher> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  bool _isMorphing = false;
  bool _isExpanded = false;
  Rect? _initialRect;
  Timer? _safetyFallbackTimer;

  @override
  void dispose() {
    _safetyFallbackTimer?.cancel();
    super.dispose();
  }

  void _triggerLaunch() {
    widget.onTap?.call();
    HapticUtils.tap();

    if (!widget.enabled) {
      // Если Liquid Glass выключен (настройки / слабые устройства),
      // используем стандартный нативный переход со свайпом назад.
      Navigator.of(context).push(
        SwipeBackPageRoute(builder: widget.destinationBuilder),
      );
      return;
    }

    if (_isMorphing) return;

    // Замеряем точное положение исходного элемента на экране
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      _initialRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    } else {
      final size = MediaQuery.sizeOf(context);
      _initialRect = Rect.fromLTWH(60, 44, size.width - 120, 44);
    }

    setState(() {
      _isMorphing = true;
      _isExpanded = false;
    });
    _overlayController.show();

    // Запускаем перетекание со следующего кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isMorphing) {
        setState(() {
          _isExpanded = true;
        });

        // Защитный таймер на случай зависания спринга физики
        _safetyFallbackTimer?.cancel();
        _safetyFallbackTimer = Timer(const Duration(milliseconds: 650), () {
          if (mounted && _isMorphing) {
            _onMorphEnd();
          }
        });
      }
    });
  }

  void _onMorphEnd() {
    _safetyFallbackTimer?.cancel();
    if (!_isMorphing) return;

    // Бесшовный Hand-off в реальный Route
    Navigator.of(context)
        .push(
      HandOffSwipeBackPageRoute(builder: widget.destinationBuilder),
    )
        .then((_) {
      // Возврат из целевого экрана: аккуратно прячем морф
      if (mounted) {
        setState(() {
          _isMorphing = false;
          _isExpanded = false;
          _initialRect = null;
        });
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: _buildOverlayContent,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Visibility(
          // Во время активного морфинга скрываем оригинал в шапке,
          // сохраняя геометрию и размеры неизменными.
          visible: !_isMorphing,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _triggerLaunch,
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent(BuildContext context) {
    if (!_isMorphing) return const SizedBox.shrink();

    final screenSize = MediaQuery.sizeOf(context);
    final fieldRect = Offset.zero & screenSize;
    final initial = _initialRect ??
        Rect.fromLTWH(60, 44, (screenSize.width - 120).clamp(100.0, 400.0), 44);

    // Рассчитываем физический якорь раскрытия из прямоугольника плашки
    final anchor = LiquidGlassMorph.alignmentFor(initial, fieldRect);
    final theme = Theme.of(context);
    final scaffoldBgColor = theme.scaffoldBackgroundColor;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Фоновый перехватчик жестов на время полета
        const Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.transparent,
          ),
        ),

        // Полноэкранный LiquidGlassMorph
        Positioned.fill(
          child: LiquidGlassMorph(
            key: const ValueKey<String>('screen_morph_container'),
            alignment: anchor,
            width: _isExpanded ? screenSize.width : initial.width,
            height: _isExpanded ? screenSize.height : initial.height,
            motion: widget.motion,
            smoothness: widget.smoothness,
            onEnd: _onMorphEnd,
            style: widget.style.copyWith(
              color: _isExpanded ? scaffoldBgColor : widget.style.color,
              blur: _isExpanded ? 0 : widget.style.blur,
              shape: LiquidGlassShape(
                cornerRadius: _isExpanded ? 0 : 22,
                cornerStyle: _isExpanded
                    ? LiquidGlassCornerStyle.squircle
                    : LiquidGlassCornerStyle.continuousRoundedRectangle,
              ),
            ),
            child: _isExpanded
                ? (widget.expandedPreviewBuilder?.call(context) ??
                    _DefaultExpandedPreview(
                      key: const ValueKey<String>('expanded_preview_step'),
                      width: screenSize.width,
                      height: screenSize.height,
                    ))
                : SizedBox(
                    key: const ValueKey<String>('collapsed_preview_step'),
                    width: initial.width,
                    height: initial.height,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Базовое плавное превью профиля на время анимации раскрытия (доли секунды).
class _DefaultExpandedPreview extends StatelessWidget {
  final double width;
  final double height;

  const _DefaultExpandedPreview({
    super.key,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: const SizedBox.expand(),
    );
  }
}
