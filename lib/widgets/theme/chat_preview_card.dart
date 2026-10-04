import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/name_color_preset.dart';
import '../../models/theav_theme.dart';
import '../../l10n/app_localizations.dart';
import '../chat/chat_scaffold.dart';
import 'four_corner_gradient.dart';
import 'motion_wallpaper_wrapper.dart';
import 'viewport_gradient_box.dart';

/// Interactive simulated chat card demonstrating active wallpaper,
/// message bubble colors, corner radius, and timestamps.
class ChatPreviewCard extends StatefulWidget {
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
  State<ChatPreviewCard> createState() => _ChatPreviewCardState();
}

class _ChatPreviewCardState extends State<ChatPreviewCard> {
  final GlobalKey _previewScopeKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = widget.theme;
    final palette = theme.palette;
    final wp = theme.wallpaper;
    final radius = theme.bubbleRadius;

    return Container(
      key: _previewScopeKey,
      height: widget.height,
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

            // 2. Exact chat messages layout
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxBubbleWidth = constraints.maxWidth * 0.78;

                  return SingleChildScrollView(
                    reverse: true,
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Date separator chip
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: palette.chatDateBadge,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                l10n?.translate('date_today') ?? 'Сегодня',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: palette.chatDateBadgeText,
                                ),
                              ),
                            ),
                          ),

                          // Incoming Bubble (Identical to real MessageBubble)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                              margin: const EdgeInsets.symmetric(vertical: 3.0),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                              decoration: BoxDecoration(
                                color: palette.chatBubbleIncoming,
                                borderRadius: BorderRadius.circular(radius),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Author Name
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3.0),
                                    child: Text(
                                      'Алексей',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: NameColorPresets.red.primaryColor,
                                      ),
                                    ),
                                  ),
                                  // Message text & timestamp
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment: WrapCrossAlignment.end,
                                    spacing: 8,
                                    runSpacing: 2,
                                    children: [
                                      Text(
                                        'Привет! Как тебе эта тема Theaver? 🎨',
                                        style: TextStyle(
                                          fontSize: 15.0,
                                          height: 1.35,
                                          color: palette.chatBubbleIncomingText,
                                        ),
                                      ),
                                      Text(
                                        '11:42',
                                        style: TextStyle(
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w500,
                                          color: palette.chatBubbleIncomingSubtext,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Outgoing Bubble (Identical to real MessageBubble)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                              margin: const EdgeInsets.symmetric(vertical: 3.0),
                              child: ViewportGradientBox(
                                borderRadius: BorderRadius.circular(radius),
                                viewportScopeKey: _previewScopeKey,
                                gradientColors: (palette.chatBubbleOutgoingGradient != null &&
                                        palette.chatBubbleOutgoingGradient!.length >= 2)
                                    ? palette.chatBubbleOutgoingGradient
                                    : null,
                                solidColor: palette.chatBubbleOutgoing,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                  child: Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.end,
                                spacing: 8,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    'Выглядит отлично! Очень стильно ✨',
                                    style: TextStyle(
                                      fontSize: 15.0,
                                      height: 1.35,
                                      color: palette.chatBubbleOutgoingText,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '11:43',
                                        style: TextStyle(
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w500,
                                          color: palette.chatBubbleOutgoingSubtext,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Icon(
                                        Icons.done_all,
                                        size: 15,
                                        color: palette.chatBubbleOutgoingSubtext,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                      ),
                    ),
                  );
                },
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperBackground(TheavWallpaper wp) {
    // 1. Base 4-corner gradient or solid color
    Widget baseBackground;
    if (wp.type == 'color') {
      baseBackground = Container(color: wp.backgroundColor);
    } else if (wp.fourCornerGradient != null) {
      final grad = wp.fourCornerGradient!;
      baseBackground = CustomPaint(
        painter: FourCornerGradientPainter(
          topLeft: grad.topLeft,
          topRight: grad.topRight,
          bottomLeft: grad.bottomLeft,
          bottomRight: grad.bottomRight,
        ),
        child: const SizedBox.expand(),
      );
    } else {
      baseBackground = Container(color: wp.backgroundColor);
    }

    Widget content;
    if (wp.type == 'image') {
      final imgProvider = wp.getImageProvider();
      if (imgProvider != null) {
        Widget img = Image(
          image: imgProvider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => baseBackground,
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
        content = baseBackground;
      }
    } else {
      // Pattern over 4-corner gradient
      final svgPath = wp.assetSvgPath;
      Widget patternWidget = const SizedBox.shrink();

      if (svgPath != null && wp.patternOpacity > 0) {
        patternWidget = TiledWallpaperPattern(
          assetPath: svgPath,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: wp.patternOpacity),
            BlendMode.srcIn,
          ),
        );
      } else if (wp.customSvgPath != null && File(wp.customSvgPath!).existsSync() && wp.patternOpacity > 0) {
        patternWidget = TiledWallpaperPattern(
          filePath: wp.customSvgPath!,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: wp.patternOpacity),
            BlendMode.srcIn,
          ),
        );
      }

      content = Stack(
        fit: StackFit.expand,
        children: [
          baseBackground,
          patternWidget,
        ],
      );
    }

    if (widget.enableMotion && wp.motionEnabled) {
      return MotionWallpaperWrapper(
        enabled: true,
        child: content,
      );
    }

    return content;
  }
}
