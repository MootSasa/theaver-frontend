import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import '../settings/settings_floating_header.dart';

/// Компактная высота верхней плавающей шапки и переключателя вкладок (`38px`).
const double kProfileFloatingBarHeight = 38.0;

/// Круглая плавающая кнопка «Назад» (`40x40`) поверх цветного/градиентного фона профиля.
class ProfileFloatingBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool glassEnabled;
  final bool isLite;
  final bool isDarkBackdrop;
  final String? tooltip;

  const ProfileFloatingBackButton({
    super.key,
    required this.onTap,
    required this.glassEnabled,
    this.isLite = false,
    this.isDarkBackdrop = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    const size = kProfileFloatingBarHeight;
    final iconColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.94)
        : const Color(0xFF1C1C1E);

    final inner = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: glassEnabled
            ? null
            : BoxDecoration(
                color: isDarkBackdrop
                    ? const Color(0xFF26262A).withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.78),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDarkBackdrop
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
        child: Center(
          child: iconoir.NavArrowLeft(
            width: 21,
            height: 21,
            color: iconColor,
          ),
        ),
      ),
    );

    Widget button;
    final glassProvider = maybeLiquidGlassProvider(context);
    if (glassEnabled && glassProvider != null) {
      final buttonStyle = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDarkBackdrop,
        isLiteOverride: isLite,
        cornerRadius: size / 2,
        color: isDarkBackdrop
            ? const Color(0x38202025)
            : const Color(0x66FFFFFF),
        refractionIndex: 1.12,
        refractionWidth: 22.0,
      );

      button = LiquidGlassLens(
        style: buttonStyle,
        touch: const LiquidGlassTouch.flexing(
          LiquidGlassFlex(
            stretch: 4,
            squeeze: 0.8,
            lean: 0.2,
          ),
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: inner,
        ),
      );
    } else {
      button = ClipOval(
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(15),
          child: inner,
        ),
      );
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Компактный переключатель разделов для классического (без Liquid Glass) режима,
/// анимируемый напрямую от [PageController] как `_buildClassicNav` в `EmojiStickerPanel`.
class ProfileClassicTopSwitcher extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final PageController pageController;
  final ValueChanged<int> onTabSelected;
  final bool isDarkBackdrop;
  final double width;
  final double height;

  const ProfileClassicTopSwitcher({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.pageController,
    required this.onTabSelected,
    required this.isDarkBackdrop,
    required this.width,
    this.height = kProfileFloatingBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final count = segments.length;
    final indicatorColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.08);
    final selectedTextColor =
        isDarkBackdrop ? Colors.white : const Color(0xFF1C1C1E);
    final unselectedTextColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF1C1C1E).withValues(alpha: 0.58);

    final navContent = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDarkBackdrop
            ? const Color(0xFF26262A).withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color: isDarkBackdrop
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: pageController,
            builder: (context, child) {
              double offset = selectedIndex.toDouble();
              try {
                if (pageController.hasClients) {
                  offset = pageController.page ?? selectedIndex.toDouble();
                }
              } catch (_) {
                offset = selectedIndex.toDouble();
              }
              final alignX = count <= 1
                  ? 0.0
                  : ((offset / (count - 1)) * 2.0 - 1.0).clamp(-1.0, 1.0);
              return Align(
                alignment: Alignment(alignX, 0),
                child: child!,
              );
            },
            child: FractionallySizedBox(
              widthFactor: 1.0 / count,
              heightFactor: 1.0,
              child: Padding(
                padding: const EdgeInsets.all(3.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (int i = 0; i < count; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTabSelected(i),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontFamily: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.fontFamily,
                            fontSize: 13.0,
                            letterSpacing: -0.2,
                            fontWeight: i == selectedIndex
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: i == selectedIndex
                                ? selectedTextColor
                                : unselectedTextColor,
                          ),
                          child: Text(
                            segments[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: navContent,
      ),
    );
  }
}

/// Полноэкранная обёртка с компактным верхним переключателем разделов и кнопкой «←»,
/// реализованная по той же архитектуре `LiquidGlassTabBar.buildGlassPillBar` + `PageController`,
/// что и в `EmojiStickerPanel`.
class ProfileFloatingSwitcherScaffold extends StatelessWidget {
  final List<String> segments;
  final int selectedIndex;
  final PageController pageController;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onBack;
  final Widget body;
  final bool glassEnabled;
  final bool isLite;
  final bool isDarkBackdrop;
  final double topMargin;
  final double horizontalMargin;

  const ProfileFloatingSwitcherScaffold({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.pageController,
    required this.onTabSelected,
    required this.onBack,
    required this.body,
    required this.glassEnabled,
    this.isLite = false,
    this.isDarkBackdrop = true,
    required this.topMargin,
    this.horizontalMargin = SettingsFloatingHeader.horizontalPadding,
  }) : assert(segments.length >= 2);

  /// Измеряет минимальную компактную ширину капсулы переключателя точно под размер слов.
  static double measureCompactWidth(
    BuildContext context,
    List<String> segments, {
    required double maxWidth,
  }) {
    if (maxWidth <= 0) return 0.0;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final fontFamily = Theme.of(context).textTheme.titleMedium?.fontFamily;
    final measureStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: 13.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    );

    double maxWordWidth = 0.0;
    for (final word in segments) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: measureStyle),
        maxLines: 1,
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout();
      if (painter.width > maxWordWidth) {
        maxWordWidth = painter.width;
      }
    }

    // По 8px компактного внутреннего отступа слева и справа от слова + 3px отступа капсулы с краёв
    final idealWidth =
        ((maxWordWidth.ceilToDouble() + 16.0) * segments.length) + 6.0;
    final minCompact = math.min(108.0, maxWidth);
    return idealWidth.clamp(minCompact, maxWidth).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = maybeLiquidGlassProvider(context);
    final useGlass = glassEnabled && glassProvider != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelW = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const barHeight = kProfileFloatingBarHeight;
        final leftOccupied =
            horizontalMargin + kProfileFloatingBarHeight + SettingsFloatingHeader.headerGap;
        final maxAvailableForBar =
            math.max(0.0, panelW - leftOccupied - horizontalMargin);
        final barWidth = measureCompactWidth(
          context,
          segments,
          maxWidth: maxAvailableForBar,
        );

        final canCenter =
            (panelW - barWidth) / 2.0 >= leftOccupied;
        final barAlignment =
            canCenter ? Alignment.topCenter : Alignment.topLeft;
        final barMargin = canCenter
            ? EdgeInsets.only(top: topMargin)
            : EdgeInsets.only(left: leftOccupied, top: topMargin);

        if (useGlass && barWidth > 0) {
          final barStyle = glassProvider.createStyle(
            context: context,
            isDarkOverride: isDarkBackdrop,
            isLiteOverride: isLite,
            cornerRadius: barHeight / 2,
            color: isDarkBackdrop
                ? const Color(0x38202025)
                : const Color(0x66FFFFFF),
            refractionIndex: 1.1,
            refractionWidth: 24.0,
          );

          final tabBar = LiquidGlassTabBar(
            items: [
              for (final label in segments)
                LiquidGlassTabBarItem(
                  label: label,
                  iconBuilder: (_, __) => const SizedBox.shrink(),
                ),
            ],
            selectedIndex: selectedIndex,
            onChanged: onTabSelected,
            width: barWidth,
            height: barHeight,
            alignment: barAlignment,
            margin: barMargin,
            itemPadding: 3,
            swell: null,
            style: barStyle,
            itemStyle: LiquidGlassTabItemStyle(
              selectedColor:
                  isDarkBackdrop ? Colors.white : const Color(0xFF1C1C1E),
              unselectedColor: isDarkBackdrop
                  ? Colors.white.withValues(alpha: 0.68)
                  : const Color(0xFF1C1C1E).withValues(alpha: 0.58),
              iconSize: 0,
              underGlassIconSize: 0,
              iconLabelGap: 0,
              labelFontSize: 13,
              underGlassLabelFontSize: 13.5,
              selectedFontWeight: FontWeight.w700,
              unselectedFontWeight: FontWeight.w600,
            ),
            pillStyle: LiquidGlassTabPillStyle(
              mode: LiquidGlassPillMode.both,
              show: true,
              animated: true,
              growHeight: 7,
              rest: LiquidGlassStyle(
                shape: const LiquidGlassShape.continuousRoundedRectangle(
                  cornerRadius: 28,
                  clipQuality: LiquidGlassClipQuality.roundedRectangle,
                ),
                color: isDarkBackdrop
                    ? const Color(0x38FFFFFF)
                    : const Color(0x2EAEAEB2),
              ),
            ),
          );

          return tabBar.buildGlassPillBar(
            body: body,
            chromeChild: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: horizontalMargin,
                  top: topMargin,
                  child: ProfileFloatingBackButton(
                    onTap: onBack,
                    glassEnabled: true,
                    isLite: isLite,
                    isDarkBackdrop: isDarkBackdrop,
                  ),
                ),
              ],
            ),
            bottomInset: 0,
            pixelRatio: 1.0,
            useSync: true,
            batch: false,
          );
        }

        final classicLeft = canCenter
            ? (panelW - barWidth) / 2.0
            : leftOccupied;

        return Stack(
          fit: StackFit.expand,
          children: [
            body,
            Positioned(
              left: horizontalMargin,
              top: topMargin,
              child: ProfileFloatingBackButton(
                onTap: onBack,
                glassEnabled: false,
                isLite: isLite,
                isDarkBackdrop: isDarkBackdrop,
              ),
            ),
            if (barWidth > 0)
              Positioned(
                left: classicLeft,
                top: topMargin,
                width: barWidth,
                height: barHeight,
                child: ProfileClassicTopSwitcher(
                  key: const ValueKey<String>('profile_classic_top_switcher'),
                  segments: segments,
                  selectedIndex: selectedIndex,
                  pageController: pageController,
                  onTabSelected: onTabSelected,
                  isDarkBackdrop: isDarkBackdrop,
                  width: barWidth,
                  height: barHeight,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Лёгкая полупрозрачная карточка секции поверх фона/градиента профиля
/// (без вложенных шейдеров/BackdropFilter внутри скролла для плавной прокрутки 120fps).
class ProfileGlassSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final bool glassEnabled;
  final bool isLite;
  final bool isDarkBackdrop;
  final Color? accentColor;
  final double dividerIndent;

  const ProfileGlassSection({
    super.key,
    this.title,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.glassEnabled = false,
    this.isLite = false,
    this.isDarkBackdrop = true,
    this.accentColor,
    this.dividerIndent = 52.0,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final baseTheme = Theme.of(context);
    final primaryText =
        isDarkBackdrop ? Colors.white : const Color(0xFF141619);
    final secondaryText = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.74)
        : const Color(0xFF4E525A);
    final sectionHeaderColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF3E424A);
    final dividerColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.black.withValues(alpha: 0.08);
    final effectiveAccent = accentColor ??
        (isDarkBackdrop ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final effectiveTextTheme = baseTheme.textTheme.apply(
      bodyColor: primaryText,
      displayColor: primaryText,
    );

    final rowsColumn = IconTheme(
      data: IconThemeData(color: primaryText),
      child: ListTileTheme(
        data: ListTileThemeData(
          iconColor: primaryText,
          textColor: primaryText,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leadingAndTrailingTextStyle: TextStyle(color: primaryText),
          titleTextStyle: baseTheme.textTheme.bodyLarge?.copyWith(
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
            color: primaryText,
          ),
          subtitleTextStyle: baseTheme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            color: secondaryText,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: primaryText),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: dividerIndent,
                      endIndent: 16,
                      color: dividerColor,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: isDarkBackdrop
            ? Colors.black.withValues(alpha: 0.34)
            : Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkBackdrop
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Theme(
          data: baseTheme.copyWith(
            brightness: isDarkBackdrop ? Brightness.dark : Brightness.light,
            textTheme: effectiveTextTheme,
            primaryTextTheme: effectiveTextTheme,
            colorScheme: baseTheme.colorScheme.copyWith(
              brightness: isDarkBackdrop ? Brightness.dark : Brightness.light,
              primary: effectiveAccent,
              onSurface: primaryText,
              onSurfaceVariant: secondaryText,
            ),
          ),
          child: rowsColumn,
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 8,
                top: 6,
              ),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: sectionHeaderColor,
                ),
              ),
            ),
          card,
        ],
      ),
    );
  }
}
