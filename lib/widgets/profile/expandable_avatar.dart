import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';

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

  /// Фактор расширения: 0.0 = маленькая круглая, 1.0 = большая квадратная
  final double expandFactor;

  /// Флаг направления (сохранён для обратной совместимости)
  final bool isCollapsing;

  /// Цвет тинта (сохранён для совместимости)
  final Color? tintColor;

  /// Цвет фона экрана
  final Color? backgroundColor;

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
    this.onPageChanged,
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
    if (widget.initialPage != null) {
      _currentPage = widget.initialPage!;
    }
  }

  void _prevPhoto() {
    if (_currentPage > 0 && widget.pageController != null && widget.pageController!.hasClients) {
      widget.pageController!.animateToPage(
        _currentPage - 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      HapticUtils.selection();
    }
  }

  void _nextPhoto() {
    if (_currentPage < widget.avatarUrls.length - 1 && widget.pageController != null && widget.pageController!.hasClients) {
      widget.pageController!.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      HapticUtils.selection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Маленький размер: 110dp диаметр (radius 55)
    const smallSize = 110.0;
    // Большой размер: 100% ширины экрана (квадрат 1:1)
    final screenWidth = MediaQuery.of(context).size.width;
    final largeSize = screenWidth;

    final progress = widget.expandFactor.clamp(0.0, 1.0);

    // Плавный непрерывный морфинг размера от 110dp до ширины экрана
    final size = lerpDouble(smallSize, largeSize, progress);

    // Плавный переход формы от круга (size/2) к квадрату (0.0)
    // easeIn обеспечивает сохранение круглой формы в начале движения
    final radiusProgress = Curves.easeIn.transform(progress);
    final borderRadius = lerpDouble(size / 2, 0.0, radiusProgress);

    // Размер иконки/буквы плейсхолдера
    final iconSize = lerpDouble(50.0, 120.0, Curves.easeInOutCubic.transform(progress));

    // Цвет фона плейсхолдера
    final bgColor = widget.backgroundColor ?? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0));

    // Сброс страницы на первую при полном сворачивании
    if (progress < 0.01 && _currentPage != 0) {
      _currentPage = 0;
    }

    final isFullyExpanded = progress >= 0.85;
    final primaryUrl = _primaryAvatarUrl;
    final currentUrl = (widget.avatarUrls.isNotEmpty && _currentPage < widget.avatarUrls.length)
        ? widget.avatarUrls[_currentPage]
        : primaryUrl;
    final targetUrl = currentUrl ?? primaryUrl;

    final bool enableInnerHero = widget.chatAvatarHeroTag == null;

    Widget avatarContent;

    if (isFullyExpanded && widget.avatarUrls.length > 1) {
      avatarContent = _buildPageView(size, size, iconSize, bgColor, isDark, Alignment.topCenter, enableInnerHero);
    } else if (_currentPage != 0 && targetUrl != null && primaryUrl != null && targetUrl != primaryUrl) {
      avatarContent = AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        child: SizedBox.expand(
          key: ValueKey(targetUrl),
          child: _buildAvatarImage(targetUrl, size, size, bgColor, iconSize, isDark, Alignment.topCenter, enableInnerHero),
        ),
      );
    } else {
      avatarContent = (primaryUrl != null && primaryUrl.isNotEmpty
          ? _buildAvatarImage(primaryUrl, size, size, bgColor, iconSize, isDark, Alignment.topCenter, enableInnerHero)
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

    Widget avatarWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
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
                    color: bgColor.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70,
                    fontSize: iconSize,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),

            // 3. Верхний градиентный скрайм для контраста индикаторов историй
            _buildTopGradientScrim(progress),

            // 4. Stories-style индикаторы нескольких фото
            _buildStoryIndicators(context, progress),

            // 5. Зоны нажатия (тапы по краям для листания, по центру — открытие галереи)
            if (isFullyExpanded && widget.avatarUrls.length > 1)
              Positioned.fill(
                child: Row(
                  children: [
                    // Левая треть: предыдущее фото
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _prevPhoto,
                      ),
                    ),
                    // Центральная область: открыть полноэкранный зум/галерею
                    Expanded(
                      flex: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: widget.onTap,
                      ),
                    ),
                    // Правая треть: следующее фото
                    Expanded(
                      flex: 3,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _nextPhoto,
                      ),
                    ),
                  ],
                ),
              )
            else
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onTap,
                ),
              ),
          ],
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

  /// Stories-style сегментированные индикаторы вверху фото
  Widget _buildStoryIndicators(BuildContext context, double progress) {
    if (widget.avatarUrls.length <= 1) return const SizedBox.shrink();

    // Плавно проявляются при приближении к полному раскрытию (от 0.65 до 1.0)
    final opacity = Curves.easeIn.transform(((progress - 0.65) / 0.35).clamp(0.0, 1.0));
    if (opacity <= 0.001) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;
    final topOffset = topPadding > 0 ? topPadding + 6.0 : 12.0;

    return Positioned(
      top: topOffset,
      left: 14.0,
      right: 14.0,
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 2.5,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Градиентный скрайм в верхней части для гарантированной читаемости индикаторов и элементов шапки
  Widget _buildTopGradientScrim(double progress) {
    final opacity = Curves.easeIn.transform(((progress - 0.5) / 0.5).clamp(0.0, 1.0));
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

  /// Строит PageView для плавного свайпа аватарок в развёрнутом режиме
  Widget _buildPageView(
    double width,
    double height,
    double iconSize,
    Color bgColor,
    bool isDark, [
    Alignment imgAlignment = Alignment.topCenter,
    bool enableHero = true,
  ]) {
    return PageView.builder(
      controller: widget.pageController,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.avatarUrls.length,
      onPageChanged: (index) {
        setState(() {
          _currentPage = index;
        });
        widget.onPageChanged?.call(index);
      },
      itemBuilder: (context, index) {
        final url = widget.avatarUrls[index];
        return _buildAvatarImage(url, width, height, bgColor, iconSize, isDark, imgAlignment, enableHero);
      },
    );
  }

  /// Линейная интерполяция double
  static double lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }

  /// Построение виджета изображения аватарки с поддержкой data:, file: и network URL
  Widget _buildAvatarImage(
    String url,
    double width,
    double height,
    Color bgColor,
    double iconSize,
    bool isDark, [
    Alignment imgAlignment = Alignment.topCenter,
    bool enableHero = true,
  ]) {
    Widget imageWidget;

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

    if (!enableHero) {
      return imageWidget;
    }

    final tag = widget.heroTagPrefix != null
        ? '${widget.heroTagPrefix}_$url'
        : 'avatar_hero_$url';

    final double initialRadius = lerpDouble(
      width / 2,
      0.0,
      Curves.easeIn.transform(widget.expandFactor.clamp(0.0, 1.0)),
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
