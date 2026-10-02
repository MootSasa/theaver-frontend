import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/theav_theme.dart';
import '../../l10n/app_localizations.dart';
import 'four_corner_gradient.dart';
import 'motion_wallpaper_wrapper.dart';

/// Interactive simulated chat card demonstrating active wallpaper,
/// message bubble colors, corner radius, and timestamps.
class ChatPreviewCard extends StatelessWidget {
  final TheavTheme theme;
  final double height;
  final bool enableMotion;

  const ChatPreviewCard({
    Key? key,
    required this.theme,
    this.height = 240,
    this.enableMotion = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = theme.palette;
    final wp = theme.wallpaper;
    final radius = theme.bubbleRadius;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Wallpaper background layer
            _buildWallpaperBackground(wp),

            // 2. Simulated messages overlay
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Date Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: palette.chatDateBadge,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.translate('date_today'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.chatDateBadgeText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Incoming Bubble
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: palette.chatBubbleIncoming,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(radius),
                          topRight: Radius.circular(radius),
                          bottomRight: Radius.circular(radius),
                          bottomLeft: Radius.circular(radius * 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Привет! Как тебе эта тема Theaver?',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: palette.chatBubbleIncomingText,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              '11:42',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: palette.chatBubbleIncomingSubtext,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Outgoing Bubble
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: palette.chatBubbleOutgoing,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(radius),
                          topRight: Radius.circular(radius),
                          bottomLeft: Radius.circular(radius),
                          bottomRight: Radius.circular(radius * 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Выглядит отлично! Градиент и узоры смотрятся очень стильно ✨',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: palette.chatBubbleOutgoingText,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '11:43',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: palette.chatBubbleOutgoingSubtext,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.done_all,
                                size: 14,
                                color: palette.chatBubbleOutgoingSubtext,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperBackground(TheavWallpaper wp) {
    Widget content;

    switch (wp.type) {
      case 'gradient4':
        final grad = wp.fourCornerGradient ?? FourCornerGradient.defaultSunset;
        content = CustomPaint(
          painter: FourCornerGradientPainter(
            topLeft: grad.topLeft,
            topRight: grad.topRight,
            bottomLeft: grad.bottomLeft,
            bottomRight: grad.bottomRight,
          ),
          child: const SizedBox.expand(),
        );
        break;

      case 'image':
        if (wp.imagePath != null && File(wp.imagePath!).existsSync()) {
          Widget img = Image.file(
            File(wp.imagePath!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          );
          if (wp.blurRadius > 0) {
            img = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: wp.blurRadius,
                sigmaY: wp.blurRadius,
              ),
              child: img,
            );
          }
          content = Stack(
            fit: StackFit.expand,
            children: [
              img,
              if (wp.dimming > 0)
                Container(
                  color: Colors.black.withValues(alpha: wp.dimming),
                ),
            ],
          );
        } else {
          content = Container(color: wp.backgroundColor);
        }
        break;

      case 'color':
        content = Container(color: wp.backgroundColor);
        break;

      case 'pattern':
      default:
        final svgPath = wp.assetSvgPath;
        Widget patternWidget = const SizedBox.shrink();

        if (svgPath != null) {
          patternWidget = SvgPicture.asset(
            svgPath,
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              wp.patternColor.withValues(alpha: wp.patternOpacity),
              BlendMode.srcIn,
            ),
          );
        } else if (wp.customSvgPath != null && File(wp.customSvgPath!).existsSync()) {
          patternWidget = SvgPicture.file(
            File(wp.customSvgPath!),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              wp.patternColor.withValues(alpha: wp.patternOpacity),
              BlendMode.srcIn,
            ),
          );
        }

        content = Stack(
          fit: StackFit.expand,
          children: [
            Container(color: wp.backgroundColor),
            patternWidget,
          ],
        );
        break;
    }

    if (enableMotion && wp.motionEnabled) {
      return MotionWallpaperWrapper(
        enabled: true,
        child: content,
      );
    }

    return content;
  }
}
