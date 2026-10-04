import 'dart:io';
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
/// a mini-chat preview matching settings theme buttons, and a bottom "ПРОСМОТР ТЕМЫ" action button.
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
  int _installCount = 0;
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
          _installCount = (data['install_count'] as num?)?.toInt() ?? 0;
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
        final double targetCardWidth = maxAvailableWidth.clamp(230.0, 320.0);

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

                          // Body Content: Theme Mini Preview + Info
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: _isLoading
                                ? SizedBox(
                                    height: 60,
                                    child: Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                        ),
                                      ),
                                    ),
                                  )
                                : (_theme != null)
                                    ? Row(
                                        children: [
                                          // Mini Theme Bubble Preview (from Settings)
                                          _buildMiniThemeBubble(_theme!),
                                          const SizedBox(width: 12),
                                          // Theme Title & Subtitle
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _theme!.name,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: widget.isDark
                                                        ? Colors.white
                                                        : const Color(0xFF1C1C1E),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  _installCount > 0
                                                      ? '${_theme!.isDark ? l10n.translate('theme_dark') : l10n.translate('theme_light')} • ${l10n.translate('theme_installs_count').replaceAll('{count}', '$_installCount')}'
                                                      : (_theme!.isDark ? l10n.translate('theme_dark') : l10n.translate('theme_light')),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: widget.isDark
                                                        ? Colors.white60
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        'https://theaver.app/addtheme/${widget.code}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: widget.isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                          ),

                          // Footer Button: "ПРОСМОТР ТЕМЫ"
                          InkWell(
                            onTap: _openPreview,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                              decoration: BoxDecoration(
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

  Widget _buildMiniThemeBubble(TheavTheme theme) {
    final wp = theme.wallpaper;

    Widget wallpaperBg;
    if (wp.type == 'image') {
      final imgProvider = wp.getImageProvider();
      if (imgProvider != null) {
        wallpaperBg = Image(
          image: imgProvider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) => Container(color: wp.backgroundColor),
        );
      } else {
        wallpaperBg = Container(color: wp.backgroundColor);
      }
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
      final double buttonPatternOpacity = (wp.patternOpacity * 1.6).clamp(0.24, 0.60);
      Widget? svgWidget;
      if (wp.customSvgPath != null && File(wp.customSvgPath!).existsSync()) {
        svgWidget = SvgPicture.file(
          File(wp.customSvgPath!),
          width: 70,
          height: 60,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      } else if (wp.assetSvgPath != null && wp.assetSvgPath!.isNotEmpty) {
        svgWidget = SvgPicture.asset(
          wp.assetSvgPath!,
          width: 70,
          height: 60,
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            wp.patternColor.withValues(alpha: buttonPatternOpacity),
            BlendMode.srcIn,
          ),
        );
      }
      if (svgWidget != null) {
        patternOverlay = svgWidget;
      }
    }

    return Container(
      width: 70,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark ? Colors.white24 : Colors.black12,
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            wallpaperBg,
            if (patternOverlay != null) patternOverlay,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Incoming oval
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 28,
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.palette.chatBubbleIncoming,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  // Outgoing oval
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 28,
                      height: 10,
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
                        borderRadius: BorderRadius.circular(5),
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
}
