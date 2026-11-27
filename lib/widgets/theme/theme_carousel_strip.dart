import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../models/theav_theme.dart';
import 'four_corner_gradient.dart';

/// Shared theme swatch card displaying wallpaper gradient/pattern, incoming and
/// outgoing bubble previews, selected state ring, and optional cloud sync badge.
class ThemeItemBubble extends StatelessWidget {
  final TheavTheme theme;
  final bool isSelected;
  final Color activePrimary;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ThemeItemBubble({
    super.key,
    required this.theme,
    required this.isSelected,
    required this.activePrimary,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final wp = theme.wallpaper;

    Widget wallpaperBg;
    if (wp.type == 'image') {
      final imgProvider = wp.getImageProvider();
      if (imgProvider != null) {
        Widget img = Image(
          image: imgProvider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) =>
              Container(color: wp.backgroundColor),
        );
        if (wp.blurRadius > 0) {
          img = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: (wp.blurRadius / 4).clamp(0.5, 4.0),
              sigmaY: (wp.blurRadius / 4).clamp(0.5, 4.0),
            ),
            child: img,
          );
        }
        if (wp.dimming > 0) {
          img = Stack(
            fit: StackFit.expand,
            children: [
              img,
              Container(
                color: Colors.black.withValues(alpha: wp.dimming.clamp(0.0, 1.0)),
              ),
            ],
          );
        }
        wallpaperBg = img;
      } else {
        wallpaperBg = Container(color: wp.backgroundColor);
      }
    } else if (wp.type == 'color') {
      wallpaperBg = Container(color: wp.backgroundColor);
    } else if (wp.fourCornerGradient != null) {
      wallpaperBg = CustomPaint(
        painter: FourCornerGradientPainter(
          topLeft: wp.fourCornerGradient!.topLeft,
          topRight: wp.fourCornerGradient!.topRight,
          bottomLeft: wp.fourCornerGradient!.bottomLeft,
          bottomRight: wp.fourCornerGradient!.bottomRight,
        ),
        child: const SizedBox.expand(),
      );
    } else {
      wallpaperBg = Container(color: wp.backgroundColor);
    }

    Widget? patternOverlay;
    if (wp.patternOpacity > 0) {
      final double buttonPatternOpacity =
          (wp.patternOpacity * 1.6).clamp(0.24, 0.60);
      Widget? svgWidget;
      if (!kIsWeb &&
          wp.customSvgPath != null &&
          File(wp.customSvgPath!).existsSync()) {
        svgWidget = SvgPicture.file(
          File(wp.customSvgPath!) as dynamic,
          width: 210.0,
          height: 210.0,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      } else if (wp.assetSvgPath != null && wp.assetSvgPath!.isNotEmpty) {
        svgWidget = SvgPicture.asset(
          wp.assetSvgPath!,
          width: 210.0,
          height: 210.0,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      }
      if (svgWidget != null) {
        patternOverlay = OverflowBox(
          minWidth: 0.0,
          maxWidth: 210.0,
          minHeight: 0.0,
          maxHeight: 210.0,
          child: svgWidget,
        );
      }
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 78,
              height: 68,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? activePrimary
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white24
                          : Colors.black12),
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: activePrimary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13.5),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    wallpaperBg,
                    if (patternOverlay != null) patternOverlay,
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 38,
                              height: 14,
                              decoration: BoxDecoration(
                                color: theme.palette.chatBubbleIncoming,
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 38,
                              height: 14,
                              decoration: BoxDecoration(
                                color: (theme.palette.chatBubbleOutgoingGradient !=
                                            null &&
                                        theme.palette.chatBubbleOutgoingGradient!
                                                .length >=
                                            2)
                                    ? null
                                    : theme.palette.chatBubbleOutgoing,
                                gradient: (theme.palette
                                                .chatBubbleOutgoingGradient !=
                                            null &&
                                        theme.palette.chatBubbleOutgoingGradient!
                                                .length >=
                                            2)
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: theme
                                            .palette.chatBubbleOutgoingGradient!,
                                      )
                                    : null,
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: activePrimary,
                            shape: BoxShape.circle,
                          ),
                          child: iconoir.Check(
                            width: 11,
                            height: 11,
                            color: theme.palette.onPrimary,
                          ),
                        ),
                      ),
                    if (theme.isCloudSaved)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const iconoir.CloudCheck(
                            width: 10,
                            height: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              theme.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? activePrimary : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable horizontal theme selector carousel shared by onboarding and ChatSettingsScreen.
class ThemeCarouselStrip extends StatelessWidget {
  final List<TheavTheme> themes;
  final TheavTheme activeTheme;
  final Color activePrimary;
  final ValueChanged<TheavTheme> onThemeSelected;
  final ValueChanged<TheavTheme>? onThemeLongPress;
  final Widget? trailingCard;
  final EdgeInsetsGeometry padding;

  const ThemeCarouselStrip({
    super.key,
    required this.themes,
    required this.activeTheme,
    required this.activePrimary,
    required this.onThemeSelected,
    this.onThemeLongPress,
    this.trailingCard,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = themes.length + (trailingCard != null ? 1 : 0);
    return SizedBox(
      height: 104,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            ui.PointerDeviceKind.touch,
            ui.PointerDeviceKind.mouse,
            ui.PointerDeviceKind.trackpad,
          },
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: totalCount,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            if (trailingCard != null && index == themes.length) {
              return trailingCard!;
            }
            final t = themes[index];
            final isSelected = t.id == activeTheme.id;
            return ThemeItemBubble(
              theme: isSelected ? activeTheme : t,
              isSelected: isSelected,
              activePrimary: activePrimary,
              onTap: () => onThemeSelected(t),
              onLongPress:
                  onThemeLongPress != null ? () => onThemeLongPress!(t) : null,
            );
          },
        ),
      ),
    );
  }
}
