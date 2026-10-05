import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../models/theav_theme.dart';
import '../../screens/settings/theme_preview_screen.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/theav_theme_service.dart';
import '../../utils/haptic_utils.dart';
import '../profile/reply_strip_painter.dart';
import '../theme/four_corner_gradient.dart';

const double _kCardBorderRadius = 6.0;
const double _kCardVerticalMargin = 4.0;

/// Interactive In-Chat Theme Link Preview Card based on [CodeBlockWidget].
/// Renders when a message contains a `theaver.app/addtheme/{code}` link.
/// Features the exact code block outer shape and left reply strip, a "ЦВЕТОВАЯ ТЕМА" header,
/// a prominent full-width theme preview (wallpaper + realistic mock chat bubbles),
/// and a bottom "ПРОСМОТР ТЕМЫ" action button.
class ThemeLinkPreviewCard extends StatefulWidget {
  final String code;
  final bool isDark;
  final bool isMe;
  final NameColorPreset? preset;
  final ReplyStripStyle? stripStyle;

  const ThemeLinkPreviewCard({
    Key? key,
    required this.code,
    required this.isDark,
    this.isMe = false,
    this.preset,
    this.stripStyle,
  }) : super(key: key);

  @override
  State<ThemeLinkPreviewCard> createState() => _ThemeLinkPreviewCardState();
}

class _ThemeLinkPreviewCardState extends State<ThemeLinkPreviewCard> {
  TheavTheme? _theme;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final data = await TheavThemeService().fetchPublicTheme(widget.code);
    if (!mounted) return;

    if (data != null && data['theme_data'] != null) {
      try {
        final parsed = TheavTheme.fromJson(data['theme_data'] as Map<String, dynamic>);
        setState(() {
          _theme = parsed;
          _isLoading = false;
        });
        return;
      } catch (e) {
        debugPrint('Error parsing preview theme: $e');
      }
    }

    setState(() => _isLoading = false);
  }

  void _openPreview() {
    HapticUtils.tap();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThemePreviewScreen(
          themeCode: widget.code,
          initialTheme: _theme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profileTheme = context.watch<ProfileThemeProvider>();
    final effectivePreset = widget.preset ?? profileTheme.currentNameColorPreset;
    final effectiveStripStyle = widget.stripStyle ?? profileTheme.currentStripStyle;

    final accentColor = effectivePreset.primaryColor;
    final cardBgColor = effectivePreset.getOpaqueCardBackgroundColor(widget.isDark);
    final cardInnerBg = widget.isDark ? const Color(0xFF191F26) : const Color(0xFFF0F4F8);
    final borderColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxAvailableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 320.0;
        final double targetCardWidth = maxAvailableWidth.clamp(240.0, 340.0);

        return MetaData(
          metaData: 'block_element',
          child: Container(
            width: targetCardWidth,
            margin: const EdgeInsets.symmetric(vertical: _kCardVerticalMargin),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(_kCardBorderRadius),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Accent Strip (Matching CodeBlockWidget)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ReplyStripWidget(
                      preset: effectivePreset,
                      style: effectiveStripStyle,
                      width: 3.5,
                      borderRadius: 2,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Inner Content Card
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardInnerBg,
                        borderRadius: BorderRadius.circular(_kCardBorderRadius - 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header: "ЦВЕТОВАЯ ТЕМА"
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: widget.isDark ? 0.2 : 0.12),
                              border: Border(
                                bottom: BorderSide(color: borderColor, width: 0.5),
                              ),
                            ),
                            child: Text(
                              l10n.translate('theme_color_theme_header').toUpperCase(),
                              style: GoogleFonts.firaCode(
                                color: accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          // Body Content: Theme Large Preview
                          GestureDetector(
                            onTap: _openPreview,
                            behavior: HitTestBehavior.opaque,
                            child: _isLoading
                                ? SizedBox(
                                    height: 150,
                                    child: Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                        ),
                                      ),
                                    ),
                                  )
                                : (_theme != null)
                                    ? _buildLargeThemePreview(_theme!)
                                    : Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          'https://theaver.app/addtheme/${widget.code}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: widget.isDark ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                      ),
                          ),

                          // Footer Button: "ПРОСМОТР ТЕМЫ"
                          InkWell(
                            onTap: _openPreview,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              decoration: BoxDecoration(
                                color: cardInnerBg,
                                border: Border(
                                  top: BorderSide(color: borderColor, width: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  iconoir.Eye(
                                    width: 14,
                                    height: 14,
                                    color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.translate('theme_view_button').toUpperCase(),
                                    style: TextStyle(
                                      color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLargeThemePreview(TheavTheme theme) {
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
          errorBuilder: (context, error, stackTrace) => Container(color: wp.backgroundColor),
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
      final double patternAlpha = (wp.patternOpacity * 1.5).clamp(0.18, 0.60);
      Widget? svgWidget;
      if (!kIsWeb && wp.customSvgPath != null && File(wp.customSvgPath!).existsSync()) {
        svgWidget = SvgPicture.file(
          File(wp.customSvgPath!) as dynamic,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: patternAlpha),
            BlendMode.srcIn,
          ),
        );
      } else if (wp.assetSvgPath != null && wp.assetSvgPath!.isNotEmpty) {
        svgWidget = SvgPicture.asset(
          wp.assetSvgPath!,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: patternAlpha),
            BlendMode.srcIn,
          ),
        );
      }
      if (svgWidget != null) {
        patternOverlay = svgWidget;
      }
    }

    final l10n = context.l10n;
    final inText = l10n.translate('theme_preview_sample_in').isNotEmpty
        ? l10n.translate('theme_preview_sample_in')
        : 'Привет! Как тебе эта тема?';
    final outText = l10n.translate('theme_preview_sample_out').isNotEmpty
        ? l10n.translate('theme_preview_sample_out')
        : 'Отличные цвета!';

    return SizedBox(
      height: 150,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Wallpaper Background
          wallpaperBg,
          if (patternOverlay != null) patternOverlay,

          // Mock Chat Bubbles
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Incoming Message Bubble
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: theme.palette.chatBubbleIncoming,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                        bottomLeft: Radius.circular(4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          inText,
                          style: TextStyle(
                            color: theme.palette.chatBubbleIncomingText,
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            '11:42',
                            style: TextStyle(
                              color: theme.palette.chatBubbleIncomingSubtext,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Outgoing Message Bubble
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: (theme.palette.chatBubbleOutgoingGradient != null &&
                              theme.palette.chatBubbleOutgoingGradient!.length >= 2)
                          ? null
                          : theme.palette.chatBubbleOutgoing,
                      gradient: (theme.palette.chatBubbleOutgoingGradient != null &&
                              theme.palette.chatBubbleOutgoingGradient!.length >= 2)
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: theme.palette.chatBubbleOutgoingGradient!,
                            )
                          : null,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          outText,
                          style: TextStyle(
                            color: theme.palette.chatBubbleOutgoingText,
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '11:43',
                              style: TextStyle(
                                color: theme.palette.chatBubbleOutgoingSubtext,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(width: 3),
                            iconoir.Check(
                              width: 10,
                              height: 10,
                              color: theme.palette.chatBubbleOutgoingSubtext,
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
    );
  }
}
