import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../services/glass_toast_service.dart';
import '../../services/profile_theme_provider.dart';
import '../profile/reply_strip_painter.dart';

// --- НАСТРОЙКИ СТИЛЯ БЛОКА КОДА ---
/// Радиус скругления основного контейнера блока кода.
const double _kCodeBlockBorderRadius = 6.0;
/// Вертикальный внешний отступ блока кода (от текста сообщения).
const double _kCodeBlockVerticalMargin = 4.0;
// ----------------------------------

class CodeBlockWidget extends StatelessWidget {
  final String code;
  final String? language;
  final bool isDark;
  final bool isMe;
  final NameColorPreset? preset;
  final ReplyStripStyle? stripStyle;

  const CodeBlockWidget({
    Key? key,
    required this.code,
    this.language,
    required this.isDark,
    this.isMe = false,
    this.preset,
    this.stripStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use the provided sender preset/stripStyle or fallback to current ProfileThemeProvider
    final profileTheme = context.watch<ProfileThemeProvider>();
    final effectivePreset = preset ?? profileTheme.currentNameColorPreset;
    final effectiveStripStyle = stripStyle ?? profileTheme.currentStripStyle;

    final accentColor = effectivePreset.primaryColor;
    final cardBgColor = effectivePreset.getOpaqueCardBackgroundColor(isDark);

    final codeBgColor = isDark ? const Color(0xFF191F26) : const Color(0xFFF0F4F8);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    // Remove background from syntax highlighting theme to use container background
    final codeTheme = Map<String, TextStyle>.from(
      isDark ? atomOneDarkTheme : atomOneLightTheme,
    );
    if (codeTheme.containsKey('root')) {
      final rootStyle = codeTheme['root']!;
      codeTheme['root'] = rootStyle.copyWith(backgroundColor: Colors.transparent);
    }

    final codeStyle = GoogleFonts.firaCode(
      fontSize: 12.5,
      height: 1.4,
    );

    final String copyCodeLabel = context.l10n.translate('format_copy_code').toUpperCase();
    final String codeCopiedMessage = context.l10n.translate('format_code_copied');

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxAvailableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 360.0;
        final double maxCodeWidth = (maxAvailableWidth - 40.0).clamp(10.0, double.infinity);

        final codePainter = TextPainter(
          text: TextSpan(text: code.trim(), style: codeStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxCodeWidth);

        double minHeaderWidth = 0.0;
        if (language != null && language!.isNotEmpty) {
          final headerPainter = TextPainter(
            text: TextSpan(
              text: language!.toUpperCase(),
              style: GoogleFonts.firaCode(
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          minHeaderWidth = headerPainter.width + 20.0;
        }

        final copyTextPainter = TextPainter(
          text: TextSpan(
            text: copyCodeLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final double minCopyWidth = copyTextPainter.width + 14.0 + 6.0 + 20.0 + 20.0;
        final double minCardWidth = math.max(minCopyWidth, minHeaderWidth + 40.0);
        final double targetCardWidth = (codePainter.width + 40.0)
            .clamp(minCardWidth, maxAvailableWidth);

        return MetaData(
          metaData: 'block_element',
          child: Container(
            width: targetCardWidth,
            margin: const EdgeInsets.symmetric(vertical: _kCodeBlockVerticalMargin),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(_kCodeBlockBorderRadius),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left Accent Bar (ReplyStripWidget)
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
                  // Code Content
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: codeBgColor,
                        borderRadius: BorderRadius.circular(_kCodeBlockBorderRadius - 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header: Language
                          if (language != null && language!.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: isDark ? 0.2 : 0.12),
                                border: Border(
                                  bottom: BorderSide(color: borderColor, width: 0.5),
                                ),
                              ),
                              child: Text(
                                language!.toUpperCase(),
                                style: GoogleFonts.firaCode(
                                  color: accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          // Code body with line wrapping
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: HighlightView(
                              code.trim(),
                              language: language ?? 'plaintext',
                              theme: codeTheme,
                              padding: EdgeInsets.zero,
                              textStyle: codeStyle,
                            ),
                          ),
                          // Footer button
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: code));
                              GlassToastService().show(
                                context, 
                                codeCopiedMessage,
                                iconWidget: iconoir.Copy(
                                  width: 18,
                                  height: 18,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: borderColor, width: 0.5),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    iconoir.Copy(
                                      width: 14,
                                      height: 14,
                                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      copyCodeLabel,
                                      style: TextStyle(
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
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
}

