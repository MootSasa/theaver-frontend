import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/image_utils.dart';

/// Аватарка с анимацией расширения по вертикальному свайпу.
///
/// По умолчанию — маленькая круглая аватарка (~110dp).
/// При свайпе вниз — плавно увеличивается и переходит в квадратную форму
/// (со скруглёнными углами), занимая ~45% высоты экрана.
/// Фиксируется в развёрнутом состоянии.
/// При обратном свайпе вверх — пружинистая анимация возврата
/// к маленькому круглому виду.
///
/// Поддерживает несколько аватарок: в развёрнутом режиме можно
/// листать их горизонтальным свайпом (PageView). В свёрнутом режиме
/// всегда отображается последняя (самая новая) аватарка.
class ExpandableAvatar extends StatefulWidget {
  /// Список URL аватарок из сети (новейшая первая)
  final List<String> avatarUrls;

  /// Локальный файл аватарки (после выбора, до сохранения)
  final File? avatarFile;

  /// Коллбэк при нажатии на аватарку
  final VoidCallback? onTap;

  /// Фактор расширения: 0.0 = маленькая круглая, 1.0 = большая квадратная
  final double expandFactor;

  /// Флаг направления: true = сворачивание (1.0 -> 0.0), false = расширение (0.0 -> 1.0)
  final bool isCollapsing;

  /// Цвет тинта внизу фото аватарки (извлечён из нижней части фото)
  final Color? tintColor;

  /// Цвет фона экрана (для размытия и тинта внизу аватарки)
  final Color? backgroundColor;

  /// Имя пользователя для плейсхолдера
  final String displayName;

  /// Префикс для Hero анимации перехода в галерею
  final String? heroTagPrefix;

  /// Опциональный тег для плавной Hero анимации между чатом и экраном профиля
  final String? chatAvatarHeroTag;

  /// Опциональный контроллер страниц для синхронизации свайпов
  final PageController? pageController;

  /// Начальный/текущий индекс страницы для синхронизации с галереей
  final int? initialPage;

  const ExpandableAvatar({
    Key? key,
    this.avatarUrls = const [],
    this.avatarFile,
    this.onTap,
    this.expandFactor = 0.0,
    this.isCollapsing = false,
    this.tintColor,
    this.backgroundColor,
    this.displayName = '',
    this.heroTagPrefix = 'avatar_hero',
    this.chatAvatarHeroTag,
    this.pageController,
    this.initialPage,
  }) : super(key: key);

  @override
  State<ExpandableAvatar> createState() => _ExpandableAvatarState();
}

class _ExpandableAvatarState extends State<ExpandableAvatar> {
  /// Текущая страница в PageView (только в развёрнутом режиме)
  int _currentPage = 0;

  /// Количество аватарок при последней перестройке (для сброса страницы)
  int _lastAvatarCount = 0;

  /// Основной URL аватарки (последняя / новейшая)
  String? get _primaryAvatarUrl {
    if (widget.avatarUrls.isNotEmpty) return widget.avatarUrls.first;
    if (widget.avatarFile != null) return widget.avatarFile!.path;
    return null;
  }

  @override
  void didUpdateWidget(ExpandableAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarUrls.length != _lastAvatarCount) {
      _lastAvatarCount = widget.avatarUrls.length;
      if (_currentPage >= widget.avatarUrls.length) {
        _currentPage = 0;
      }
    }
    if (widget.initialPage != null && widget.initialPage != oldWidget.initialPage) {
      _currentPage = widget.initialPage!;
    }
  }

  @override
  void initState() {
    super.initState();
    _lastAvatarCount = widget.avatarUrls.length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Маленький размер: 110dp диаметр (radius 55)
    const smallSize = 110.0;
    // Большой размер: 100% ширины экрана
    final screenWidth = MediaQuery.of(context).size.width;
    final largeSize = screenWidth;

    final progress = widget.expandFactor.clamp(0.0, 1.0);

    final double size;
    final double borderRadius;

    // Пороги переломного момента (чуть дальше: 0.32 и 0.68)
    const expandThreshold = 0.32;
    const collapseThreshold = 0.68;

    if (widget.isCollapsing) {
      // Режим сворачивания (1.0 -> 0.0):
      if (progress >= collapseThreshold) {
        // При потягивании вверх аватарка слегка подаётся вверх, НЕ меняя полноэкранный размер и прямоугольную форму
        size = largeSize;
        borderRadius = 0.0;
      } else {
        // После переломного момента (0.68) — аватарка БЫСТРО и плавно сворачивается в маленький круг
        final collapseProgress = (progress / collapseThreshold).clamp(0.0, 1.0);
        final collapseFactor = Curves.easeInQuart.transform(collapseProgress);

        size = lerpDouble(smallSize, largeSize, collapseFactor);
        final currentCircleRadius = size / 2;
        borderRadius = lerpDouble(currentCircleRadius, 0.0, collapseFactor);
      }
    } else {
      // Режим расширения (0.0 -> 1.0):
      if (progress < expandThreshold) {
        // Изначально аватарка круглая, при растягивании до порога (0.32) чуть пойдёт вниз и увеличится (110 -> 145dp), оставаясь круглой
        final preProgress = (progress / expandThreshold).clamp(0.0, 1.0);
        final preFactor = Curves.easeOutCubic.transform(preProgress);
        size = lerpDouble(smallSize, 145.0, preFactor);
        borderRadius = size / 2; // Строго круглая
      } else {
        // После переломного момента аватарка расширяется до полноэкранной
        final expansionProgress = ((progress - expandThreshold) / (1.0 - expandThreshold)).clamp(0.0, 1.0);
        final fastSizeFactor = Curves.easeOutQuart.transform(expansionProgress);

        size = lerpDouble(145.0, largeSize, fastSizeFactor);

        // Быстрый переход формы из круга в квадрат
        final fastShapeProgress = (expansionProgress / 0.25).clamp(0.0, 1.0);
        final shapeFactor = Curves.easeOutCubic.transform(fastShapeProgress);

        final currentCircleRadius = size / 2;
        borderRadius = lerpDouble(currentCircleRadius, 0.0, shapeFactor);
      }
    }

    // Интерполяция размера иконки плейсхолдера
    final iconSize = lerpDouble(50.0, 120.0, Curves.easeInOutCubic.transform(progress));

    // Цвет фона плейсхолдера (из переданного backgroundColor или из темы)
    final bgColor = widget.backgroundColor ?? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0));

    // Определяем URL для отображения в свёрнутом режиме
    final displayUrl = _primaryAvatarUrl;

    // Отзеркаленная 10% часть при сворачивании до переломного момента (0.68) остаётся 100% цельной (прямоугольник 110%)
    final double mirrorProgress;
    if (widget.isCollapsing) {
      if (progress >= collapseThreshold) {
        mirrorProgress = 1.0;
      } else {
        mirrorProgress = (progress / collapseThreshold).clamp(0.0, 1.0);
      }
    } else {
      mirrorProgress = ((progress - 0.85) / 0.15).clamp(0.0, 1.0);
    }

    final mirrorFactor = Curves.easeOutCubic.transform(mirrorProgress);
    final mirrorHeight = (size * 0.10) * mirrorFactor;

    // До переломного момента при сворачивании totalHeight остается полноэкранной (110% прямоугольник)
    final totalHeight = size + mirrorHeight;

    // При полном сворачивании к круглой аватарке всегда сбрасываем текущую страницу на 0 (самую актуальную)
    if (widget.expandFactor < 0.01 && _currentPage != 0) {
      _currentPage = 0;
    }

    final isFullyExpanded = widget.expandFactor >= 0.95;
    final primaryUrl = _primaryAvatarUrl;
    final currentUrl = (widget.avatarUrls.isNotEmpty && _currentPage < widget.avatarUrls.length)
        ? widget.avatarUrls[_currentPage]
        : primaryUrl;

    // Отображаем текущее выбранное фото (для совпадения Hero-тегов при анимации закрытия)
    final targetUrl = currentUrl ?? primaryUrl;

    Widget avatarContent;

    final bool enableInnerHero = widget.chatAvatarHeroTag == null;

    if (isFullyExpanded && widget.avatarUrls.length > 1) {
      avatarContent = _buildPageView(size, size, iconSize, bgColor, isDark, Alignment.topCenter, enableInnerHero);
    } else if (_currentPage != 0 && targetUrl != null && primaryUrl != null && targetUrl != primaryUrl) {
      avatarContent = AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        child: SizedBox.expand(
          key: ValueKey(targetUrl),
          child: _buildAvatarImage(targetUrl, size, size, bgColor, iconSize, isDark, Alignment.topCenter, enableInnerHero),
        ),
      );
    } else {
      avatarContent = (displayUrl != null && displayUrl.isNotEmpty
          ? _buildAvatarImage(displayUrl, size, size, bgColor, iconSize, isDark, Alignment.topCenter, enableInnerHero)
          : (widget.avatarFile != null
              ? Image.file(
                  widget.avatarFile!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  width: size,
                  height: size,
                )
              : const SizedBox.expand()));
    }

    Widget avatarWidget = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: totalHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Основная аватарка (100% высоты квадратного формата size x size)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: size,
                child: Container(
                  color: bgColor,
                  child: avatarContent,
                ),
              ),
              // Отзеркаленная нижняя часть (Hero отключен для предотвращения мерцания/дрожания)
              if (mirrorHeight > 0.0)
                Positioned(
                  top: size - 0.5,
                  left: 0,
                  right: 0,
                  height: mirrorHeight + 0.5,
                  child: Opacity(
                    opacity: mirrorFactor,
                    child: ClipRect(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationX(math.pi),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: size, // Жестко фиксируем исходный размер, чтобы пропорции картинки не ломались при кропе
                              child: Container(
                                color: bgColor,
                                child: currentUrl != null && currentUrl.isNotEmpty
                                    ? _buildAvatarImage(currentUrl, size, size, bgColor, iconSize, isDark, Alignment.topCenter, false)
                                    : (displayUrl != null && displayUrl.isNotEmpty
                                        ? _buildAvatarImage(displayUrl, size, size, bgColor, iconSize, isDark, Alignment.topCenter, false)
                                        : (widget.avatarFile != null
                                            ? Image.file(
                                                widget.avatarFile!,
                                                fit: BoxFit.cover,
                                                alignment: Alignment.topCenter,
                                                width: size,
                                                height: size,
                                              )
                                            : null)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Плейсхолдер с буквой
              if (widget.avatarFile == null && (widget.avatarUrls.isEmpty))
                Center(
                  child: Text(
                    widget.displayName.isNotEmpty
                        ? widget.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: bgColor.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70,
                      fontSize: iconSize,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),

            ],
          ),
        ),
      ),
    );

    if (widget.chatAvatarHeroTag != null) {
      avatarWidget = Hero(
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
        child: avatarWidget,
      );
    }

    return avatarWidget;
  }

  /// Строит PageView для свайпа аватарок в развёрнутом режиме
  Widget _buildPageView(double width, double height, double iconSize, Color bgColor, bool isDark, [Alignment imgAlignment = Alignment.topCenter, bool enableHero = true]) {
    return PageView.builder(
      controller: widget.pageController,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.avatarUrls.length,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
      },
      itemBuilder: (context, index) {
        final url = widget.avatarUrls[index];
        return GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: _buildAvatarImage(url, width, height, bgColor, iconSize, isDark, imgAlignment, enableHero),
        );
      },
    );
  }

  /// Линейная интерполяция double
  static double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }

  /// Build avatar image that supports data: URLs (base64), local files, and network URLs
  Widget _buildAvatarImage(String url, double width, double height, Color bgColor, double iconSize, bool isDark, [Alignment imgAlignment = Alignment.topCenter, bool enableHero = true]) {
    Widget imageWidget;

    // Handle data: URLs (base64 encoded avatars stored in DB)
    if (url.startsWith('data:')) {
      try {
        final commaIndex = url.indexOf(',');
        if (commaIndex == -1) {
          return _avatarErrorWidget(bgColor, iconSize, isDark);
        }
        final base64Str = url.substring(commaIndex + 1);
        final bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          alignment: imgAlignment,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) =>
              _avatarErrorWidget(bgColor, iconSize, isDark),
        );
      } catch (_) {
        return _avatarErrorWidget(bgColor, iconSize, isDark);
      }
    } else if (url.startsWith('file://')) {
      try {
        final filePath = Uri.parse(url).toFilePath();
        final file = File(filePath);
        if (file.existsSync()) {
          imageWidget = Image.file(
            file,
            fit: BoxFit.cover,
            alignment: imgAlignment,
            width: width,
            height: height,
            errorBuilder: (context, error, stackTrace) =>
                _avatarErrorWidget(bgColor, iconSize, isDark),
          );
        } else {
          imageWidget = _avatarErrorWidget(bgColor, iconSize, isDark);
        }
      } catch (_) {
        imageWidget = _avatarErrorWidget(bgColor, iconSize, isDark);
      }
    } else {
      final localFile = File(url);
      if (localFile.existsSync()) {
        imageWidget = Image.file(
          localFile,
          fit: BoxFit.cover,
          alignment: imgAlignment,
          width: width,
          height: height,
          errorBuilder: (context, error, stackTrace) =>
              _avatarErrorWidget(bgColor, iconSize, isDark),
        );
      } else {
        final validUrl = getValidAvatarUrl(url);
        if (validUrl != null && (validUrl.startsWith('http://') || validUrl.startsWith('https://'))) {
          imageWidget = CachedNetworkImage(
            imageUrl: validUrl,
            fit: BoxFit.cover,
            alignment: imgAlignment,
            width: width,
            height: height,
            placeholder: (context, _) => Container(
              width: width,
              height: height,
              color: bgColor,
            ),
            errorWidget: (context, _, __) =>
                _avatarErrorWidget(bgColor, iconSize, isDark),
          );
        } else {
          imageWidget = _avatarErrorWidget(bgColor, iconSize, isDark);
        }
      }
    }

    // Если Hero отключен (например для нижней отзеркаленной части), возвращаем чистый виджет без Hero
    if (!enableHero) {
      return imageWidget;
    }

    final tag = widget.heroTagPrefix != null
        ? '${widget.heroTagPrefix}_$url'
        : 'avatar_hero_$url';

    final double initialRadius;
    if (widget.isCollapsing) {
      if (widget.expandFactor >= 0.5) {
        initialRadius = 0.0;
      } else {
        final collapseProgress = (widget.expandFactor.clamp(0.0, 1.0) / 0.5).clamp(0.0, 1.0);
        final collapseFactor = Curves.easeInOutCubic.transform(collapseProgress);
        initialRadius = lerpDouble(width / 2, 0.0, collapseFactor);
      }
    } else {
      final heroProgress = ((widget.expandFactor.clamp(0.0, 1.0) - 0.5) / 0.5).clamp(0.0, 1.0);
      final heroShapeFactor = Curves.easeOutCubic.transform(heroProgress);
      initialRadius = lerpDouble(width / 2, 0.0, heroShapeFactor);
    }

    return Hero(
      tag: tag,
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        final CurvedAnimation curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
        );
        return AnimatedBuilder(
          animation: curvedAnimation,
          builder: (context, child) {
            final double currentRadius = lerpDouble(initialRadius, 0.0, curvedAnimation.value);
            return ClipRRect(
              borderRadius: BorderRadius.circular(currentRadius),
              child: toHeroContext.widget,
            );
          },
        );
      },
      child: imageWidget,
    );
  }

  Widget _avatarErrorWidget(Color bgColor, double iconSize, bool isDark) {
    return Container(
      color: bgColor,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: bgColor.computeLuminance() > 0.5 ? Colors.black38 : Colors.white38,
          size: iconSize,
        ),
      ),
    );
  }
}
