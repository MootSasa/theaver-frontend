import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../config/app_config.dart';
import '../../models/profile_customization.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../tiling/tile_viewport_scope.dart';
import '../user/avatar_decoration_frame.dart';

/// Аватарка с Telegram-подобной анимацией плавного раскрытия.
///
/// В свёрнутом состоянии — компактная круглая аватарка (~110dp).
/// При потягивании вниз — непрерывный и плавный морфинг в полноэкранный квадрат (1:1),
/// без пороговых рывков и без искусственных отражений.
///
/// Поддерживает несколько аватарок:
/// - Сегментированные индикаторы-полоски вверху (Stories-style)
/// - Горизонтальный свайп через нативный [PageView]
/// - Быстрое переключение по тапу на левую/правую треть фото
/// - Одиночный тап по центру для открытия полноэкранного просмотра
class ExpandableAvatar extends StatefulWidget {
  /// Список URL аватарок из сети (новейшая первая)
  final List<String> avatarUrls;

  /// Локальный файл аватарки (после выбора, до сохранения)
  final File? avatarFile;

  /// Коллбэк при нажатии на аватарку
  final VoidCallback? onTap;

  /// Непрерывный фактор морфинга в стиле Telegram: 0.0 = круглая аватарка, 1.0 = полноширинный квадрат 1:1
  final double expandFactor;

  /// Эластичное преднатяжение круглой аватарки при потягивании вниз до порога раскрытия (0.0 .. 1.0 -> 110..136dp круг)
  final double pullPreviewProgress;

  /// Опциональный диаметр свёрнутого состояния (используется для бесшовного стыка со скролл-метаболом)
  final double? collapsedDiameterOverride;

  /// Опциональная высота развёрнутого фото (в Telegram при скролле вверх фото сначала уходит/подрезается вверх
  /// по высоте без уменьшения ширины `screenWidth`, и только после порога `expandProgress < 0.33` сворачивается в круг)
  final double? expandedHeightOverride;

  /// Прогресс перетягивания вниз поверх уже раскрытой аватарки (0.0 .. 1.0) для Telegram-зума
  final double overExpandProgress;

  /// Величина опережения нижнего контента относительно аватарки при натяжении сворачивания (в dp),
  /// на которую поднимается нижняя граница альфа-растворения фото, чтобы имя не заходило под аватарку и её блюр
  final double bottomCollapseOverlap;

  /// Флаг направления (сохранён для обратной совместимости)
  final bool isCollapsing;

  /// Цвет тинта (сохранён для совместимости)
  final Color? tintColor;

  /// Цвет фона экрана
  final Color? backgroundColor;

  /// Декорация рамки вокруг круглой аватарки (плавно растворяется при раскрытии)
  final AvatarDecorationPreset? decoration;

  /// Показывать ли встроенный оверлей декорации внутри [ExpandableAvatar].
  /// Отключается, когда внешний слой метабола рисует рамку отдельным необрезаемым компаньоном.
  final bool showDecoration;

  /// Имя пользователя для плейсхолдера
  final String displayName;

  /// Префикс для Hero анимации
  final String? heroTagPrefix;

  /// Опциональный тег для плавной Hero анимации между чатом и экраном профиля
  final String? chatAvatarHeroTag;

  /// Опциональный контроллер страниц для синхронизации свайпов
  final PageController? pageController;

  /// Начальный/текущий индекс страницы для синхронизации с галереей
  final int? initialPage;

  /// Уведомление о смене активной аватарки
  final ValueChanged<int>? onPageChanged;

  /// Опциональный обработчик начала вертикального перетаскивания
  final GestureDragStartCallback? onVerticalDragStart;

  /// Опциональный обработчик вертикального перетаскивания (для плавного сворачивания/разворачивания)
  final GestureDragUpdateCallback? onVerticalDragUpdate;

  /// Опциональный обработчик завершения вертикального перетаскивания
  final GestureDragEndCallback? onVerticalDragEnd;

  const ExpandableAvatar({
    Key? key,
    this.avatarUrls = const [],
    this.avatarFile,
    this.onTap,
    this.expandFactor = 0.0,
    this.pullPreviewProgress = 0.0,
    this.collapsedDiameterOverride,
    this.expandedHeightOverride,
    this.overExpandProgress = 0.0,
    this.bottomCollapseOverlap = 0.0,
    this.isCollapsing = false,
    this.tintColor,
    this.backgroundColor,
    this.decoration,
    this.showDecoration = true,
    this.displayName = '',
    this.heroTagPrefix = 'avatar_hero',
    this.chatAvatarHeroTag,
    this.pageController,
    this.initialPage,
    this.onPageChanged,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  }) : super(key: key);

  static const double baseCollapsedSize = 110.0;
  static const double maxPullPreviewExtraSize = 28.0;

  /// Вычисляет размер круглой аватарки с учётом эластичного потягивания вниз до порога раскрытия (`110 -> 136dp`),
  /// как в Telegram (`ProfileActivity`: `avatarScale` `96 -> 138` до срабатывания `isPulledDown`).
  static double calculateCollapsedPreviewSize({
    double baseSize = baseCollapsedSize,
    double pullPreviewProgress = 0.0,
    double expandFactor = 0.0,
  }) {
    final preview = Curves.easeOutQuad.transform(
      pullPreviewProgress.clamp(0.0, 1.0),
    );
    final fadeOut = (1.0 - expandFactor.clamp(0.0, 1.0));
    return baseSize + maxPullPreviewExtraSize * preview * fadeOut;
  }

  /// Гладкая линейная интерполяция размера между кругом и полноширинным квадратом (`1:1`) без излома на `0.38`
  /// (вся динамика разгона/торможения задаётся кривой/пружиной самого `expandFactor`, как в Telegram).
  static double calculateAvatarSize(
    double screenWidth,
    double expandFactor, {
    double pullPreviewProgress = 0.0,
    double? collapsedSizeOverride,
  }) {
    final p = expandFactor.clamp(0.0, 1.0);
    final startSize = calculateCollapsedPreviewSize(
      baseSize: collapsedSizeOverride ?? baseCollapsedSize,
      pullPreviewProgress: pullPreviewProgress,
      expandFactor: p,
    );
    return startSize + (screenWidth - startSize) * p;
  }

  /// Непрерывное скругление углов от полного круга (`size / 2` при `0.0`) до квадрата (`0.0` при `1.0`),
  /// начинающее скруглять квадрат с первой же миллисекунды сворачивания (`ProfileActivity.setRoundRadiusForExpand`).
  static double calculateBorderRadius(double size, double expandFactor) {
    final p = expandFactor.clamp(0.0, 1.0);
    return (size * 0.5) * (1.0 - p);
  }

  @override
  State<ExpandableAvatar> createState() => _ExpandableAvatarState();
}

class _ExpandableAvatarState extends State<ExpandableAvatar> {
  static const int _kInfiniteLoopMultiplier = 10000;
  static const int _kInfiniteCenterBase = 5000;

  final GlobalKey _pageViewKey = GlobalKey();
  late PageController _loopPageController;

  /// Текущий реальный индекс аватарки (0 .. avatarUrls.length - 1)
  int _currentPage = 0;

  /// Текущая виртуальная страница в бесконечном PageView
  int _currentVirtualPage = 0;

  /// Количество аватарок при последней перестройке (для синхронизации виртуальной страницы)
  int _lastAvatarCount = 0;

  /// Основной URL аватарки (последняя / новейшая)
  String? get _primaryAvatarUrl {
    if (widget.avatarUrls.isNotEmpty) return widget.avatarUrls.first;
    if (widget.avatarFile != null) return widget.avatarFile!.path;
    return null;
  }

  int _virtualPageForRealIndex(int realIndex, int count) {
    if (count <= 1) return 0;
    final safeReal = ((realIndex % count) + count) % count;
    if (_currentVirtualPage > 0) {
      final currentReal = ((_currentVirtualPage % count) + count) % count;
      int diff = safeReal - currentReal;
      if (diff > count ~/ 2) diff -= count;
      if (diff < -(count ~/ 2)) diff += count;
      return _currentVirtualPage + diff;
    }
    return _kInfiniteCenterBase * count + safeReal;
  }

  void _ensureLoopControllerSynced() {
    final count = widget.avatarUrls.length;
    if (count <= 1) return;
    if (_currentVirtualPage <= 0) {
      _currentVirtualPage =
          _kInfiniteCenterBase * count + _currentPage.clamp(0, count - 1);
    }
    if (!_loopPageController.hasClients &&
        _loopPageController.initialPage != _currentVirtualPage) {
      _loopPageController.dispose();
      _loopPageController = PageController(initialPage: _currentVirtualPage);
    }
  }

  @override
  void initState() {
    super.initState();
    _lastAvatarCount = widget.avatarUrls.length;
    if (widget.initialPage != null && _lastAvatarCount > 0) {
      _currentPage = widget.initialPage!.clamp(0, _lastAvatarCount - 1);
    }
    _currentVirtualPage = _lastAvatarCount > 1
        ? _kInfiniteCenterBase * _lastAvatarCount + _currentPage
        : 0;
    _loopPageController = PageController(initialPage: _currentVirtualPage);
  }

  @override
  void didUpdateWidget(ExpandableAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.avatarUrls.length;
    // При начале сворачивания из квадрата в круг плавно возвращаем карусель к главному фото (0)
    if (widget.expandFactor < 0.98 && oldWidget.expandFactor >= 0.98) {
      if (_currentPage != 0 && count > 1) {
        _currentPage = 0;
        _currentVirtualPage = _virtualPageForRealIndex(0, count);
        if (_loopPageController.hasClients) {
          _loopPageController.animateToPage(
            _currentVirtualPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    }

    if (count != _lastAvatarCount) {
      _lastAvatarCount = count;
      if (count == 0 || _currentPage >= count) {
        _currentPage = 0;
      }
      _currentVirtualPage =
          count > 1 ? _kInfiniteCenterBase * count + _currentPage : 0;
      if (_loopPageController.hasClients && count > 1) {
        _loopPageController.jumpToPage(_currentVirtualPage);
      } else {
        _loopPageController.dispose();
        _loopPageController = PageController(initialPage: _currentVirtualPage);
      }
    } else if (widget.initialPage != null &&
        widget.initialPage != oldWidget.initialPage &&
        count > 0) {
      final targetReal = widget.initialPage!.clamp(0, count - 1);
      if (targetReal != _currentPage) {
        _currentPage = targetReal;
        if (count > 1) {
          _currentVirtualPage = _virtualPageForRealIndex(targetReal, count);
          if (_loopPageController.hasClients) {
            final bool isCoveredByFullscreenViewer =
                ModalRoute.of(context)?.isCurrent == false;
            if (widget.expandFactor < 0.98 && !isCoveredByFullscreenViewer) {
              _loopPageController.animateToPage(
                _currentVirtualPage,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
              );
            } else {
              _loopPageController.jumpToPage(_currentVirtualPage);
            }
          } else {
            _loopPageController.dispose();
            _loopPageController =
                PageController(initialPage: _currentVirtualPage);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _loopPageController.dispose();
    super.dispose();
  }

  void _prevPhoto() {
    final count = widget.avatarUrls.length;
    if (count <= 1) return;
    if (_loopPageController.hasClients) {
      final currentVirtual =
          _loopPageController.page?.round() ?? _currentVirtualPage;
      _loopPageController.animateToPage(
        currentVirtual - 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else {
      final targetPage = _currentPage > 0 ? _currentPage - 1 : count - 1;
      setState(() {
        _currentPage = targetPage;
        _currentVirtualPage = _virtualPageForRealIndex(targetPage, count);
      });
      widget.onPageChanged?.call(targetPage);
    }
    HapticUtils.selection();
  }

  void _nextPhoto() {
    final count = widget.avatarUrls.length;
    if (count <= 1) return;
    if (_loopPageController.hasClients) {
      final currentVirtual =
          _loopPageController.page?.round() ?? _currentVirtualPage;
      _loopPageController.animateToPage(
        currentVirtual + 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } else {
      final targetPage = _currentPage < count - 1 ? _currentPage + 1 : 0;
      setState(() {
        _currentPage = targetPage;
        _currentVirtualPage = _virtualPageForRealIndex(targetPage, count);
      });
      widget.onPageChanged?.call(targetPage);
    }
    HapticUtils.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final screenWidth = TileViewportScope.widthOf(context);
    final largeSize = screenWidth;
    final progress = widget.expandFactor.clamp(0.0, 1.0);
    final extraOverPullSize = 36.0 *
        Curves.easeOutCubic
            .transform(widget.overExpandProgress.clamp(0.0, 1.0));

    final boxWidth = ExpandableAvatar.calculateAvatarSize(
          largeSize,
          progress,
          pullPreviewProgress: widget.pullPreviewProgress,
          collapsedSizeOverride: widget.collapsedDiameterOverride,
        ) +
        extraOverPullSize;
    final fullExpandedHeight = widget.expandedHeightOverride ?? largeSize;
    final boxHeight = ExpandableAvatar.calculateAvatarSize(
          fullExpandedHeight,
          progress,
          pullPreviewProgress: widget.pullPreviewProgress,
          collapsedSizeOverride: widget.collapsedDiameterOverride,
        ) +
        extraOverPullSize;

    final minBoxDim = math.min(boxWidth, boxHeight);
    final borderRadius =
        ExpandableAvatar.calculateBorderRadius(minBoxDim, progress);

    // Размер иконки/буквы плейсхолдера
    final iconProgress = Curves.easeInOutCubic.transform(progress);
    final iconSize = lerpDouble(50.0, 120.0, iconProgress);

    // Цвет фона плейсхолдера
    final bgColor = widget.backgroundColor ?? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0));

    // Сброс страницы на первую при полном сворачивании
    if (progress < 0.01 && _currentPage != 0) {
      _currentPage = 0;
      if (widget.avatarUrls.length > 1) {
        _currentVirtualPage =
            _kInfiniteCenterBase * widget.avatarUrls.length;
      }
    }

    final isFullyExpanded = progress >= 0.85;
    final primaryUrl = _primaryAvatarUrl;
    final currentUrl = (widget.avatarUrls.isNotEmpty && _currentPage < widget.avatarUrls.length)
        ? widget.avatarUrls[_currentPage]
        : primaryUrl;
    final targetUrl = currentUrl ?? primaryUrl;

    // В развёрнутом режиме (или когда внешний тег отключён для открытия просмотрщика)
    // включаем внутренний Hero для плавного перелёта самой аватарки в полноэкранный просмотр.
    final bool enableInnerHero =
        widget.chatAvatarHeroTag == null || isFullyExpanded;

    Widget avatarContent;

    if (isFullyExpanded && widget.avatarUrls.length > 1) {
      avatarContent = _buildPageView(boxWidth, boxHeight, iconSize, bgColor, isDark, Alignment.center, enableInnerHero);
    } else if (_currentPage != 0 && targetUrl != null && primaryUrl != null && targetUrl != primaryUrl) {
      avatarContent = AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        child: SizedBox.expand(
          key: ValueKey(targetUrl),
          child: _buildAvatarImage(targetUrl, boxWidth, boxHeight, bgColor, iconSize, isDark, Alignment.center, enableInnerHero),
        ),
      );
    } else {
      avatarContent = (primaryUrl != null && primaryUrl.isNotEmpty
          ? _buildAvatarImage(primaryUrl, boxWidth, boxHeight, bgColor, iconSize, isDark, Alignment.center, enableInnerHero)
          : (widget.avatarFile != null
              ? Image.file(
                  widget.avatarFile!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  width: boxWidth,
                  height: boxHeight,
                )
              : const SizedBox.expand()));
    }

    final dissolveProgress = Curves.easeInOutCubic
        .transform(((progress - 0.15) / 0.85).clamp(0.0, 1.0));

    Widget innerStack = Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.expand,
      children: [
        // 1. Основное изображение аватарки
        Positioned.fill(
          child: Container(
            color: bgColor,
            child: avatarContent,
          ),
        ),

        // 2. Буквенный плейсхолдер если нет фото
        if (widget.avatarFile == null && widget.avatarUrls.isEmpty)
          Center(
            child: Text(
              widget.displayName.isNotEmpty
                  ? widget.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: bgColor.computeLuminance() > 0.5
                    ? Colors.black54
                    : Colors.white70,
                fontSize: iconSize,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),

        // 3. Верхний градиентный скрайм для контраста индикаторов историй
        _buildTopGradientScrim(progress),

        // 4. Stories-style индикаторы нескольких фото
        _buildStoryIndicators(context, progress),
      ],
    );

    // Истинное альфа-растворение нижней кромки развёрнутой аватарки в реальный фон/градиент экрана
    if (dissolveProgress > 0.001) {
      final safeHeight = math.max(1.0, boxHeight);
      final overlapShift =
          (widget.bottomCollapseOverlap * dissolveProgress).clamp(0.0, safeHeight * 0.45);
      final endStop = ((safeHeight - overlapShift) / safeHeight).clamp(0.10, 1.0);
      final dissolveHeight = 44.0 * dissolveProgress;
      final startStop =
          (endStop - (dissolveHeight / safeHeight)).clamp(0.0, endStop);
      final midStop =
          (startStop + (endStop - startStop) * 0.55).clamp(startStop, endStop);

      innerStack = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, startStop, midStop, endStop, 1.0],
            colors: [
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 1.0 - 0.55 * dissolveProgress),
              Colors.white.withValues(alpha: 1.0 - 1.0 * dissolveProgress),
              Colors.white.withValues(alpha: 1.0 - 1.0 * dissolveProgress),
            ],
          ).createShader(bounds);
        },
        child: innerStack,
      );
    }

    Widget avatarContentBox = Container(
      width: boxWidth,
      height: boxHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: innerStack,
      ),
    );

    if (widget.chatAvatarHeroTag != null && !isFullyExpanded) {
      avatarContentBox = Hero(
        tag: widget.chatAvatarHeroTag!,
        flightShuttleBuilder: (
          flightContext,
          animation,
          flightDirection,
          fromHeroContext,
          toHeroContext,
        ) {
          final targetWidget = flightDirection == HeroFlightDirection.push
              ? toHeroContext.widget
              : fromHeroContext.widget;
          return ClipOval(
            child: Material(
              type: MaterialType.transparency,
              child: FittedBox(
                fit: BoxFit.cover,
                child: targetWidget,
              ),
            ),
          );
        },
        child: avatarContentBox,
      );
    }

    Widget finalChild = avatarContentBox;
    final dec = widget.decoration;
    if (widget.showDecoration && dec != null && progress < 0.28) {
      final frameOpacity =
          (1.0 - (progress / 0.26).clamp(0.0, 1.0)).clamp(0.0, 1.0);
      if (frameOpacity > 0.001) {
        finalChild = Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            avatarContentBox,
            IgnorePointer(
              child: AvatarDecorationFrame(
                decoration: dec,
                avatarDiameter: minBoxDim,
                opacity: frameOpacity,
                child: SizedBox(width: minBoxDim, height: minBoxDim),
              ),
            ),
          ],
        );
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isFullyExpanded && widget.avatarUrls.length > 1 ? null : widget.onTap,
      onVerticalDragStart: widget.onVerticalDragStart,
      onVerticalDragUpdate: widget.onVerticalDragUpdate,
      onVerticalDragEnd: widget.onVerticalDragEnd,
      child: finalChild,
    );
  }

  /// Stories-style сегментированные индикаторы вверху фото
  Widget _buildStoryIndicators(
    BuildContext context,
    double progress, [
    double overPullFade = 1.0,
  ]) {
    if (widget.avatarUrls.length <= 1) return const SizedBox.shrink();

    // Плавно проявляются при приближении к полному раскрытию (от 0.65 до 1.0)
    final opacity = Curves.easeIn
            .transform(((progress - 0.65) / 0.35).clamp(0.0, 1.0)) *
        overPullFade;
    if (opacity <= 0.001) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;
    final topOffset = topPadding > 0 ? topPadding + 6.0 : 12.0;

    return Positioned(
      top: topOffset,
      left: 14.0,
      right: 14.0,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Row(
            children: List.generate(widget.avatarUrls.length, (index) {
              final isCurrent = index == _currentPage;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 2.0),
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Градиентный скрайм в верхней части для гарантированной читаемости индикаторов и элементов шапки
  Widget _buildTopGradientScrim(double progress, [double overPullFade = 1.0]) {
    final opacity =
        Curves.easeIn.transform(((progress - 0.5) / 0.5).clamp(0.0, 1.0)) *
            overPullFade;
    if (opacity <= 0.001) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 72.0,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.40 * opacity),
                Colors.transparent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
    );
  }

  /// Строит PageView для плавного бесконечного свайпа аватарок в развёрнутом режиме
  Widget _buildPageView(
    double width,
    double height,
    double iconSize,
    Color bgColor,
    bool isDark, [
    Alignment imgAlignment = Alignment.center,
    bool enableHero = true,
  ]) {
    _ensureLoopControllerSynced();
    final count = widget.avatarUrls.length;
    return SwipeBackBlocker(
      child: PageView.builder(
        key: _pageViewKey,
        controller: _loopPageController,
        physics: const BouncingScrollPhysics(),
        itemCount: count * _kInfiniteLoopMultiplier,
        onPageChanged: (virtualIndex) {
        if (count == 0) return;
        _currentVirtualPage = virtualIndex;
        final realIndex = ((virtualIndex % count) + count) % count;
        if (_currentPage != realIndex) {
          setState(() {
            _currentPage = realIndex;
          });
          widget.onPageChanged?.call(realIndex);
        }
      },
      itemBuilder: (context, virtualIndex) {
        if (count == 0) return const SizedBox.shrink();
        final realIndex = ((virtualIndex % count) + count) % count;
        final url = widget.avatarUrls[realIndex];
        final currentVirtual = _loopPageController.hasClients
            ? (_loopPageController.page?.round() ??
                _virtualPageForRealIndex(_currentPage, count))
            : _virtualPageForRealIndex(_currentPage, count);
        final isActiveVirtualPage = virtualIndex == currentVirtual;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final dx = details.localPosition.dx;
            final w = width;
            if (count > 1) {
              if (dx < w * 0.30) {
                _prevPhoto();
              } else if (dx > w * 0.70) {
                _nextPhoto();
              } else {
                widget.onTap?.call();
              }
            } else {
              widget.onTap?.call();
            }
          },
          child: _buildAvatarImage(
            url,
            width,
            height,
            bgColor,
            iconSize,
            isDark,
            imgAlignment,
            enableHero && isActiveVirtualPage,
          ),
        );
        },
      ),
    );
  }

  /// Линейная интерполяция double
  static double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }

  Widget _buildRawAvatarSource(
    String cleanUrl, {
    required double width,
    required double height,
    required BoxFit fit,
    required Alignment alignment,
    required Color bgColor,
    required double iconSize,
    required bool isDark,
  }) {
    if (cleanUrl.startsWith('data:')) {
      final provider = avatarFullImageProvider(cleanUrl);
      if (provider != null) {
        return Image(
          image: provider,
          fit: fit,
          alignment: alignment,
          width: width,
          height: height,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              _avatarErrorWidget(bgColor, iconSize, isDark),
        );
      }
      return _avatarErrorWidget(bgColor, iconSize, isDark);
    }

    if (!kIsWeb && cleanUrl.startsWith('file://')) {
      try {
        final filePath = Uri.parse(cleanUrl).toFilePath();
        final file = File(filePath);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: fit,
            alignment: alignment,
            width: width,
            height: height,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) =>
                _avatarErrorWidget(bgColor, iconSize, isDark),
          );
        }
        return _avatarErrorWidget(bgColor, iconSize, isDark);
      } catch (_) {
        return _avatarErrorWidget(bgColor, iconSize, isDark);
      }
    }

    if (!kIsWeb && File(cleanUrl).existsSync()) {
      return Image.file(
        File(cleanUrl),
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _avatarErrorWidget(bgColor, iconSize, isDark),
      );
    }

    final validUrl = stripAvatarCropFragment(getValidAvatarUrl(cleanUrl));
    if (validUrl != null &&
        (validUrl.startsWith('http://') || validUrl.startsWith('https://'))) {
      return CachedNetworkImage(
        imageUrl: validUrl,
        cacheKey: AppConfig.cacheKeyForUrl(validUrl),
        httpHeaders: AppConfig.authHeadersForUrl(validUrl),
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, _) => Container(
          width: width,
          height: height,
          color: bgColor,
        ),
        errorWidget: (context, _, __) =>
            _avatarErrorWidget(bgColor, iconSize, isDark),
      );
    }

    return _avatarErrorWidget(bgColor, iconSize, isDark);
  }

  Widget _buildFramedAvatarBox({
    required String cleanUrl,
    required AvatarCropSpec? miniCrop,
    required double boxWidth,
    required double boxHeight,
    required double expandT,
    required bool lockToSquareScale,
    required Color bgColor,
    required double iconSize,
    required bool isDark,
    required Alignment imgAlignment,
  }) {
    final double safeW = math.max(1.0, boxWidth);
    final double safeH = math.max(1.0, boxHeight);
    final bool hasSubCrop = miniCrop != null && !miniCrop.isFullSquare;

    if (hasSubCrop) {
      final double imgAspect = miniCrop.imageAspectRatio.clamp(0.2, 5.0);
      final double wCover;
      final double hCover;
      final double x1;
      final double y1;
      final double cx1;
      final double cy1;
      final double refSide;

      if (lockToSquareScale) {
        final double squareSide = math.max(safeW, safeH);
        wCover = imgAspect >= 1.0 ? squareSide * imgAspect : squareSide;
        hCover = imgAspect >= 1.0 ? squareSide : squareSide / imgAspect;
        x1 = (squareSide * 0.5 - miniCrop.cx * wCover)
            .clamp(squareSide - wCover, 0.0);
        y1 = (squareSide * 0.5 - miniCrop.cy * hCover)
            .clamp(squareSide - hCover, 0.0);
        cx1 = (squareSide * 0.5 - x1) / math.max(1e-6, wCover);
        cy1 = (squareSide * 0.5 - y1) / math.max(1e-6, hCover);
        refSide = squareSide;
      } else {
        final double boxAspect = safeW / safeH;
        wCover = imgAspect >= boxAspect ? safeH * imgAspect : safeW;
        hCover = imgAspect >= boxAspect ? safeH : safeW / imgAspect;
        x1 = (safeW * 0.5 - miniCrop.cx * wCover).clamp(safeW - wCover, 0.0);
        y1 = (safeH * 0.5 - miniCrop.cy * hCover).clamp(safeH - hCover, 0.0);
        cx1 = (safeW * 0.5 - x1) / math.max(1e-6, wCover);
        cy1 = (safeH * 0.5 - y1) / math.max(1e-6, hCover);
        refSide = math.min(safeW, safeH);
      }

      final double miniSideAtCover = math.max(1e-6, miniCrop.nw * wCover);
      final double zoom0 = math.max(1.0, refSide / miniSideAtCover);
      final double t = expandT.clamp(0.0, 1.0);
      final double invZoom = lerpDouble(1.0 / zoom0, 1.0, t);
      final double zoom = invZoom > 1e-6 ? (1.0 / invZoom) : 1.0;
      final double wRender = wCover * zoom;
      final double hRender = hCover * zoom;
      final double focusX = lerpDouble(miniCrop.cx, cx1, t);
      final double focusY = lerpDouble(miniCrop.cy, cy1, t);
      final double xRender =
          (safeW * 0.5 - focusX * wRender).clamp(safeW - wRender, 0.0);
      final double yRender =
          (safeH * 0.5 - focusY * hRender).clamp(safeH - hRender, 0.0);

      return SizedBox(
        width: safeW,
        height: safeH,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: xRender,
                top: yRender,
                width: wRender,
                height: hRender,
                child: _buildRawAvatarSource(
                  cleanUrl,
                  width: wRender,
                  height: hRender,
                  fit: BoxFit.fill,
                  alignment: Alignment.center,
                  bgColor: bgColor,
                  iconSize: iconSize,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (lockToSquareScale && safeH < safeW - 0.5) {
      final double squareSide = safeW;
      return SizedBox(
        width: safeW,
        height: safeH,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: (safeW - squareSide) * 0.5,
                top: (safeH - squareSide) * 0.5,
                width: squareSide,
                height: squareSide,
                child: _buildRawAvatarSource(
                  cleanUrl,
                  width: squareSide,
                  height: squareSide,
                  fit: BoxFit.cover,
                  alignment: imgAlignment,
                  bgColor: bgColor,
                  iconSize: iconSize,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildRawAvatarSource(
      cleanUrl,
      width: safeW,
      height: safeH,
      fit: BoxFit.cover,
      alignment: imgAlignment,
      bgColor: bgColor,
      iconSize: iconSize,
      isDark: isDark,
    );
  }

  /// Построение виджета изображения аватарки с поддержкой data:, file: и network URL
  Widget _buildAvatarImage(
    String url,
    double width,
    double height,
    Color bgColor,
    double iconSize,
    bool isDark, [
    Alignment imgAlignment = Alignment.center,
    bool enableHero = true,
  ]) {
    final ({String? cleanUrl, AvatarCropSpec? crop}) split =
        AvatarCropSpec.split(url);
    final String cleanUrl = split.cleanUrl ?? url;
    final AvatarCropSpec? miniCrop = split.crop;
    final double clampedExpand = widget.expandFactor.clamp(0.0, 1.0);

    final Widget imageWidget = _buildFramedAvatarBox(
      cleanUrl: cleanUrl,
      miniCrop: miniCrop,
      boxWidth: width,
      boxHeight: height,
      expandT: clampedExpand,
      lockToSquareScale: true,
      bgColor: bgColor,
      iconSize: iconSize,
      isDark: isDark,
      imgAlignment: imgAlignment,
    );

    if (!enableHero) {
      return imageWidget;
    }

    final tag = widget.heroTagPrefix != null
        ? '${widget.heroTagPrefix}_$url'
        : 'avatar_hero_$url';

    final double initialRadius = ExpandableAvatar.calculateBorderRadius(
      math.min(width, height),
      clampedExpand,
    );

    return Hero(
      tag: tag,
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final double rawT = animation.value.clamp(0.0, 1.0);
              final double tFlight = flightDirection == HeroFlightDirection.push
                  ? Curves.easeOutCubic.transform(rawT)
                  : Curves.easeInCubic.transform(rawT);
              final double currentRadius = lerpDouble(initialRadius, 0.0, tFlight);
              final double shuttleExpand = lerpDouble(clampedExpand, 1.0, tFlight);
              return ClipRRect(
                borderRadius: BorderRadius.circular(currentRadius),
                child: Material(
                  type: MaterialType.transparency,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double bw = constraints.maxWidth.isFinite &&
                              constraints.maxWidth > 0.0
                          ? constraints.maxWidth
                          : math.max(1.0, width);
                      final double bh = constraints.maxHeight.isFinite &&
                              constraints.maxHeight > 0.0
                          ? constraints.maxHeight
                          : math.max(1.0, height);
                      return _buildFramedAvatarBox(
                        cleanUrl: cleanUrl,
                        miniCrop: miniCrop,
                        boxWidth: bw,
                        boxHeight: bh,
                        expandT: shuttleExpand,
                        lockToSquareScale: false,
                        bgColor: bgColor,
                        iconSize: iconSize,
                        isDark: isDark,
                        imgAlignment: imgAlignment,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
      child: imageWidget,
    );
  }

  Widget _avatarErrorWidget(Color bgColor, double iconSize, bool isDark) {
    final color = bgColor.computeLuminance() > 0.5 ? Colors.black38 : Colors.white38;
    return Container(
      color: bgColor,
      child: Center(
        child: iconoir.MediaImage(
          color: color,
          width: iconSize,
          height: iconSize,
        ),
      ),
    );
  }
}
