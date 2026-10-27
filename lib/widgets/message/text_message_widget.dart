import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/name_color_preset.dart';
import '../../models/theav_theme.dart';
import '../../screens/settings/theme_preview_screen.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/theav_theme_service.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/entity_parser.dart';
import 'code_block_widget.dart';
import 'collapsible_blockquote_widget.dart';
import 'spoiler_text_widget.dart';

// --- НАСТРОЙКИ СТИЛЯ ТЕКСТОВОГО СООБЩЕНИЯ ---
/// Стандартный размер шрифта сообщений.
const double _kMessageFontSize = 17.0;
// --------------------------------------------

/// Descriptor for a top-level message segment (either a contiguous inline text range
/// or a single block-level entity such as `pre`, `blockquote`, or `latex_block`).
class _MessageSegment {
  final int start;
  final int end;
  final MessageEntity? blockEntity;

  const _MessageSegment.inline({
    required this.start,
    required this.end,
  }) : blockEntity = null;

  const _MessageSegment.block({
    required this.start,
    required this.end,
    required MessageEntity this.blockEntity,
  });

  bool get isBlock => blockEntity != null;
}

/// Виджет для отображения текстового сообщения на базе прямого Entity-First парсера.
///
/// Рендерит [MessageEntity] напрямую в лёгкие деревья [InlineSpan] и блочные виджеты
/// без промежуточной обратной сериализации в Markdown и без тяжёлого AST `MarkdownBody`.
class TextMessageWidget extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool isMe;
  final List<MessageEntity>? entities;
  final NameColorPreset? nameColorPreset;
  final ReplyStripStyle? replyStripStyle;

  const TextMessageWidget({
    Key? key,
    required this.text,
    this.style,
    this.isMe = false,
    this.entities,
    this.nameColorPreset,
    this.replyStripStyle,
  }) : super(key: key);

  /// Preserves consecutive spaces and multiple enters inside message text,
  /// while trimming only spaces and enters at the very end.
  /// Content inside code blocks and LaTeX formulas is left untouched.
  static String preserveWhitespace(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return '';

    final pattern = RegExp(
      r'(```[\s\S]*?```|`[^`\n]*?`|\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)|(?<!\\|\$)\$(?!\$|\s)(?:\\.|[^\\\n\$])+?(?<!\s|\\)\$(?!\$|\d))',
    );
    final buffer = StringBuffer();
    int lastIndex = 0;

    for (final match in pattern.allMatches(trimmed)) {
      if (match.start > lastIndex) {
        buffer.write(_preserveInNormalText(trimmed.substring(lastIndex, match.start)));
      }
      buffer.write(match.group(0)!);
      lastIndex = match.end;
    }
    if (lastIndex < trimmed.length) {
      buffer.write(_preserveInNormalText(trimmed.substring(lastIndex)));
    }
    return buffer.toString();
  }

  static String _preserveInNormalText(String text) {
    var result = text.replaceAllMapped(RegExp(r' {2,}'), (match) {
      final len = match.group(0)!.length;
      final sb = StringBuffer();
      for (int i = 0; i < len; i++) {
        sb.write(i % 2 == 1 ? '\u00A0' : ' ');
      }
      return sb.toString();
    });

    result = result.replaceAllMapped(RegExp(r'\n{2,}(?!\s*\|)'), (match) {
      final count = match.group(0)!.length;
      final sb = StringBuffer();
      for (int i = 0; i < count - 1; i++) {
        sb.write('\n\u00A0');
      }
      sb.write('\n');
      return sb.toString();
    });

    return result;
  }

  static const int _kMaxSpanCacheSize = 512;
  static final Map<int, TextSpan> _richSpanCache = <int, TextSpan>{};

  static const Set<String> _kBlockEntityTypes = {
    'pre',
    'blockquote',
    'quote',
    'collapse',
    'expandable_blockquote',
    'latex_block',
  };

  static const Set<String> _kPureStyleInlineTypes = {
    'bold',
    'italic',
    'underline',
    'strikethrough',
  };

  static bool _isBlockType(String type) => _kBlockEntityTypes.contains(type);

  static bool _isQuoteType(String type) =>
      type == 'blockquote' ||
      type == 'quote' ||
      type == 'collapse' ||
      type == 'expandable_blockquote';

  static TextSpan _buildPureStyleInlineSpan(
    String cleanText,
    List<MessageEntity> entities,
    TextStyle baseStyle,
  ) {
    final points = <int>{0, cleanText.length};
    for (final e in entities) {
      final s = e.offset.clamp(0, cleanText.length);
      final end = (e.offset + e.length).clamp(s, cleanText.length);
      if (s < end) {
        points.add(s);
        points.add(end);
      }
    }
    final sortedPoints = points.toList()..sort();
    final children = <InlineSpan>[];

    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final segStart = sortedPoints[i];
      final segEnd = sortedPoints[i + 1];
      if (segStart >= segEnd) continue;

      final segText = cleanText.substring(segStart, segEnd);
      TextStyle segStyle = baseStyle;

      bool isBold = false;
      bool isItalic = false;
      bool isUnderline = false;
      bool isStrike = false;

      for (final e in entities) {
        if (e.offset <= segStart && (e.offset + e.length) >= segEnd) {
          switch (e.type) {
            case 'bold':
              isBold = true;
              break;
            case 'italic':
              isItalic = true;
              break;
            case 'underline':
              isUnderline = true;
              break;
            case 'strikethrough':
              isStrike = true;
              break;
          }
        }
      }

      if (isBold) {
        segStyle = segStyle.copyWith(fontWeight: FontWeight.bold);
      }
      if (isItalic) {
        segStyle = segStyle.copyWith(fontStyle: FontStyle.italic);
      }
      if (isUnderline || isStrike) {
        segStyle = segStyle.copyWith(
          decoration: (isUnderline && isStrike)
              ? TextDecoration.combine([
                  TextDecoration.underline,
                  TextDecoration.lineThrough,
                ])
              : (isUnderline
                  ? TextDecoration.underline
                  : TextDecoration.lineThrough),
          decorationColor: segStyle.color,
          decorationThickness: isUnderline ? 1.5 : null,
        );
      }

      children.add(EmojiUtils.buildEmojiTextSpan(segText, style: segStyle));
    }

    return TextSpan(style: baseStyle, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color messageTextColor = style?.color ??
        theme.textTheme.bodyMedium?.color ??
        (isDark ? Colors.white : Colors.black);

    // IMPORTANT: Never add EmojiUtils.fontFallbacks ('AppleEmoji') to base TextStyle,
    // because AppleColorEmoji.ttf contains full-em spaces (U+0020) and keycap base
    // digits (0-9, #, *). Emojis are styled exclusively via EmojiUtils.buildEmojiTextSpan.
    final double effectiveFontSize = style?.fontSize ?? _kMessageFontSize;
    final TextStyle effectiveStyle =
        (style ?? theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: messageTextColor,
      fontSize: effectiveFontSize,
      height: 1.12,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final StrutStyle tightStrut = StrutStyle(
      fontSize: effectiveFontSize,
      height: 1.12,
      leading: 0.0,
      leadingDistribution: TextLeadingDistribution.even,
      forceStrutHeight: true,
    );

    final parsed = EntityParser.resolveMessageEntities(text, entities);
    final cleanText = parsed.cleanText;
    final resolvedEntities = parsed.entities;

    // Fast-path 1: Plain text with zero entities
    if (resolvedEntities.isEmpty) {
      if (EmojiUtils.hasPotentialEmoji(cleanText)) {
        final spanKey = Object.hash(
          1,
          cleanText,
          effectiveStyle.color,
          effectiveStyle.fontSize,
          effectiveStyle.fontWeight,
        );
        TextSpan? cachedSpan = _richSpanCache[spanKey];
        if (cachedSpan == null) {
          cachedSpan = EmojiUtils.buildEmojiTextSpan(
            cleanText,
            style: effectiveStyle,
          );
          if (_richSpanCache.length >= _kMaxSpanCacheSize) {
            _richSpanCache.remove(_richSpanCache.keys.first);
          }
          _richSpanCache[spanKey] = cachedSpan;
        }
        return MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Text.rich(
            cachedSpan,
            strutStyle: tightStrut,
          ),
        );
      }
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Text(
          cleanText,
          style: effectiveStyle,
          strutStyle: tightStrut,
        ),
      );
    }

    // Fast-path 2: Only pure style inline entities (bold, italic, underline, strikethrough)
    // without links, spoilers, code, blocks, or LaTeX -> single cached Text.rich
    final bool isPureStyleInline = resolvedEntities.every(
      (e) => _kPureStyleInlineTypes.contains(e.type),
    );
    if (isPureStyleInline) {
      final entitiesHash = Object.hashAll(
        resolvedEntities.map((e) => Object.hash(e.type, e.offset, e.length)),
      );
      final spanKey = Object.hash(
        2,
        cleanText,
        entitiesHash,
        effectiveStyle.color,
        effectiveStyle.fontSize,
      );
      TextSpan? cachedSpan = _richSpanCache[spanKey];
      if (cachedSpan == null) {
        cachedSpan = _buildPureStyleInlineSpan(
          cleanText,
          resolvedEntities,
          effectiveStyle,
        );
        if (_richSpanCache.length >= _kMaxSpanCacheSize) {
          _richSpanCache.remove(_richSpanCache.keys.first);
        }
        _richSpanCache[spanKey] = cachedSpan;
      }
      return MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Text.rich(
          cachedSpan,
          strutStyle: tightStrut,
        ),
      );
    }

    final themeExt = theme.extension<TheavThemeExtension>();
    final Color linkColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoingLink ??
            (isDark ? const Color(0xFF7BE5DA) : const Color(0xFF007AFF)))
        : (themeExt?.palette.chatBubbleIncomingLink ??
            (isDark ? const Color(0xFF7BE5DA) : theme.colorScheme.primary));

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: DefaultTextStyle.merge(
        style: effectiveStyle,
        child: _DirectEntityMessageRenderer(
          cleanText: cleanText,
          entities: resolvedEntities,
          baseStyle: effectiveStyle,
          linkColor: linkColor,
          isDark: isDark,
          isMe: isMe,
          nameColorPreset: nameColorPreset,
          replyStripStyle: replyStripStyle,
        ),
      ),
    );
  }
}

class _DirectEntityMessageRenderer extends StatefulWidget {
  final String cleanText;
  final List<MessageEntity> entities;
  final TextStyle baseStyle;
  final Color linkColor;
  final bool isDark;
  final bool isMe;
  final NameColorPreset? nameColorPreset;
  final ReplyStripStyle? replyStripStyle;

  const _DirectEntityMessageRenderer({
    required this.cleanText,
    required this.entities,
    required this.baseStyle,
    required this.linkColor,
    required this.isDark,
    required this.isMe,
    this.nameColorPreset,
    this.replyStripStyle,
  });

  @override
  State<_DirectEntityMessageRenderer> createState() =>
      _DirectEntityMessageRendererState();
}

class _DirectEntityMessageRendererState
    extends State<_DirectEntityMessageRenderer> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(covariant _DirectEntityMessageRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cleanText != widget.cleanText ||
        oldWidget.entities != widget.entities) {
      _disposeRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _createTapRecognizer(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  Future<void> _handleLinkTap(String rawHref) async {
    final trimmed = rawHref.trim();
    if (trimmed.isEmpty) return;

    final normalized = EntityParser.normalizeUrl(trimmed);
    final themeCode = TheavThemeService.extractThemeCode(normalized);
    if (themeCode != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ThemePreviewScreen(themeCode: themeCode),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(normalized);
    if (uri != null) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        debugPrint('Error launching URL $uri: $e');
      }
    }
  }

  void _handleCodeCopy(String codeText) {
    Clipboard.setData(ClipboardData(text: codeText));
    if (mounted) {
      GlassToastService().show(context, 'Код скопирован', icon: Icons.check);
    }
  }

  static String _extractCleanLatex(String rawText) {
    final text = rawText.trim();
    if ((text.startsWith(r'$$') && text.endsWith(r'$$') && text.length >= 4) ||
        (text.startsWith(r'\[') && text.endsWith(r'\]') && text.length >= 4) ||
        (text.startsWith(r'\(') && text.endsWith(r'\)') && text.length >= 4)) {
      return text.substring(2, text.length - 2).trim();
    }
    if (text.startsWith(r'$') && text.endsWith(r'$') && text.length >= 2) {
      return text.substring(1, text.length - 1).trim();
    }
    return text;
  }

  Widget _buildLatexWidget(
    String rawFormula,
    TextStyle effectiveStyle, {
    required bool isDisplayMode,
  }) {
    final mathContent = _extractCleanLatex(rawFormula);
    final textColor = effectiveStyle.color ??
        (widget.isDark ? Colors.white : Colors.black);
    final fontSize = effectiveStyle.fontSize ?? _kMessageFontSize;

    if (mathContent.isEmpty) {
      return Text(rawFormula, style: effectiveStyle);
    }

    final mathTextStyle = effectiveStyle.copyWith(
      color: textColor,
      fontStyle: FontStyle.normal,
      fontSize: fontSize,
    );

    final Widget mathWidget = DefaultTextStyle.merge(
      style: mathTextStyle,
      child: IconTheme.merge(
        data: IconThemeData(color: textColor),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Math.tex(
            mathContent,
            mathStyle: isDisplayMode ? MathStyle.display : MathStyle.text,
            textStyle: mathTextStyle,
            options: MathOptions(
              style: isDisplayMode ? MathStyle.display : MathStyle.text,
              color: textColor,
              fontSize: fontSize,
            ),
            onErrorFallback: (err) => Text(
              rawFormula,
              style: mathTextStyle.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    );

    if (isDisplayMode) {
      return MetaData(
        metaData: 'block_element',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: mathWidget,
        ),
      );
    }

    return mathWidget;
  }

  /// Splits [textLength] into non-overlapping top-level block and inline segments.
  static List<_MessageSegment> _splitIntoSegments(
    String text,
    List<MessageEntity> entities,
  ) {
    final blockEntities = <MessageEntity>[];
    for (final e in entities) {
      if (!TextMessageWidget._isBlockType(e.type)) continue;
      final s = e.offset.clamp(0, text.length);
      final end = (e.offset + e.length).clamp(s, text.length);
      if (s >= end) continue;
      // Ignore if overlapping a previously accepted outer block
      final overlaps = blockEntities.any((b) {
        final bEnd = b.offset + b.length;
        return s < bEnd && end > b.offset;
      });
      if (!overlaps) {
        blockEntities.add(e.copyWith(offset: s, length: end - s));
      }
    }

    if (blockEntities.isEmpty) {
      return [_MessageSegment.inline(start: 0, end: text.length)];
    }

    blockEntities.sort((a, b) => a.offset.compareTo(b.offset));
    final segments = <_MessageSegment>[];
    int cursor = 0;

    for (final block in blockEntities) {
      final bStart = block.offset;
      final bEnd = block.offset + block.length;
      if (bStart > cursor) {
        int inlineStart = cursor;
        int inlineEnd = bStart;
        // Strip a single newline separating an earlier block and this inline segment
        if (segments.isNotEmpty &&
            segments.last.isBlock &&
            inlineStart < inlineEnd &&
            text.codeUnitAt(inlineStart) == 0x0A) {
          inlineStart++;
        }
        // Strip a single newline right before the upcoming block
        if (inlineEnd > inlineStart && text.codeUnitAt(inlineEnd - 1) == 0x0A) {
          inlineEnd--;
        }
        if (inlineStart < inlineEnd) {
          segments.add(_MessageSegment.inline(start: inlineStart, end: inlineEnd));
        }
      }
      segments.add(_MessageSegment.block(
        start: bStart,
        end: bEnd,
        blockEntity: block,
      ));
      cursor = bEnd;
    }

    if (cursor < text.length) {
      int inlineStart = cursor;
      final int inlineEnd = text.length;
      if (segments.isNotEmpty &&
          segments.last.isBlock &&
          inlineStart < inlineEnd &&
          text.codeUnitAt(inlineStart) == 0x0A) {
        inlineStart++;
      }
      if (inlineStart < inlineEnd) {
        segments.add(_MessageSegment.inline(start: inlineStart, end: inlineEnd));
      }
    }

    return segments;
  }

  /// Builds an inline [RichText] widget for the range `[rangeStart, rangeEnd]`
  /// with full support for nested/overlapping formatting, links, tap-to-copy code,
  /// inline LaTeX formulas, emojis, and Telegram-style inline spoilers.
  Widget _buildInlineRangeWidget({
    required String fullText,
    required int rangeStart,
    required int rangeEnd,
    required List<MessageEntity> allEntities,
    required TextStyle rangeBaseStyle,
    required Color rangeLinkColor,
  }) {
    if (rangeStart >= rangeEnd) return const SizedBox.shrink();

    // Collect inline entities intersecting [rangeStart, rangeEnd]
    final localEntities = <MessageEntity>[];
    final spoilerRanges = <InlineSpoilerRange>[];
    int nextSpoilerId = 1;

    for (final e in allEntities) {
      if (TextMessageWidget._isBlockType(e.type)) continue;
      final s = e.offset < rangeStart ? rangeStart : e.offset;
      final end = (e.offset + e.length) > rangeEnd
          ? rangeEnd
          : (e.offset + e.length);
      if (s >= end) continue;

      final localStart = s - rangeStart;
      final localEnd = end - rangeStart;
      localEntities.add(e.copyWith(offset: localStart, length: localEnd - localStart));

      if (e.type == 'spoiler') {
        spoilerRanges.add(InlineSpoilerRange(
          id: nextSpoilerId++,
          start: localStart,
          end: localEnd,
        ));
      }
    }

    final segmentText = fullText.substring(rangeStart, rangeEnd);
    final bool hasInlineLatex = localEntities.any(
      (e) => e.type == 'latex_inline',
    );
    final StrutStyle? strutStyle = hasInlineLatex
        ? null
        : StrutStyle(
            fontSize: rangeBaseStyle.fontSize ?? _kMessageFontSize,
            height: rangeBaseStyle.height ?? 1.12,
            leading: 0.0,
            leadingDistribution: TextLeadingDistribution.even,
            forceStrutHeight: true,
          );

    if (localEntities.isEmpty) {
      if (EmojiUtils.hasPotentialEmoji(segmentText)) {
        return Text.rich(
          EmojiUtils.buildEmojiTextSpan(segmentText, style: rangeBaseStyle),
          strutStyle: strutStyle,
        );
      }
      return Text(
        segmentText,
        style: rangeBaseStyle,
        strutStyle: strutStyle,
      );
    }

    InlineSpan buildSpanTree(Set<int> hiddenSpoilerIds) {
      final points = <int>{0, segmentText.length};
      for (final e in localEntities) {
        points.add(e.offset.clamp(0, segmentText.length));
        points.add((e.offset + e.length).clamp(0, segmentText.length));
      }
      for (final sr in spoilerRanges) {
        points.add(sr.start.clamp(0, segmentText.length));
        points.add(sr.end.clamp(0, segmentText.length));
      }
      final sortedPoints = points.toList()..sort();
      final children = <InlineSpan>[];

      int i = 0;
      while (i < sortedPoints.length - 1) {
        final sliceStart = sortedPoints[i];
        final sliceEnd = sortedPoints[i + 1];
        if (sliceStart >= sliceEnd) {
          i++;
          continue;
        }

        // Check if this slice begins an inline LaTeX formula
        MessageEntity? inlineLatex;
        for (final e in localEntities) {
          if (e.type == 'latex_inline' &&
              e.offset <= sliceStart &&
              (e.offset + e.length) >= sliceEnd) {
            inlineLatex = e;
            break;
          }
        }

        bool isSpoilerHidden = false;
        for (final sr in spoilerRanges) {
          if (sr.start <= sliceStart &&
              sr.end >= sliceEnd &&
              hiddenSpoilerIds.contains(sr.id)) {
            isSpoilerHidden = true;
            break;
          }
        }

        if (inlineLatex != null) {
          final latexEnd = (inlineLatex.offset + inlineLatex.length)
              .clamp(sliceEnd, segmentText.length);
          final formulaRaw = inlineLatex.language ??
              segmentText.substring(inlineLatex.offset, latexEnd);

          Widget mathChild = _buildLatexWidget(
            formulaRaw,
            rangeBaseStyle,
            isDisplayMode: false,
          );
          if (isSpoilerHidden) {
            mathChild = Opacity(opacity: 0.0, child: mathChild);
          }

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: mathChild,
            ),
          );

          // Advance i past latexEnd
          while (i < sortedPoints.length - 1 && sortedPoints[i] < latexEnd) {
            i++;
          }
          continue;
        }

        final sliceText = segmentText.substring(sliceStart, sliceEnd);
        TextStyle sliceStyle = rangeBaseStyle;

        bool isBold = false;
        bool isItalic = false;
        bool isUnderline = false;
        bool isStrike = false;
        bool isCode = false;
        String? linkUrl;

        for (final e in localEntities) {
          if (e.offset <= sliceStart && (e.offset + e.length) >= sliceEnd) {
            switch (e.type) {
              case 'bold':
                isBold = true;
                break;
              case 'italic':
                isItalic = true;
                break;
              case 'underline':
                isUnderline = true;
                break;
              case 'strikethrough':
                isStrike = true;
                break;
              case 'code':
                isCode = true;
                break;
              case 'url':
              case 'link':
              case 'text_link':
                linkUrl = (e.url != null && e.url!.isNotEmpty)
                    ? e.url!
                    : segmentText.substring(e.offset, e.offset + e.length);
                break;
            }
          }
        }

        if (isBold) {
          sliceStyle = sliceStyle.copyWith(fontWeight: FontWeight.bold);
        }
        if (isItalic) {
          sliceStyle = sliceStyle.copyWith(fontStyle: FontStyle.italic);
        }

        final bool hasLink = linkUrl != null && linkUrl.isNotEmpty;
        if (hasLink) {
          sliceStyle = sliceStyle.copyWith(color: rangeLinkColor);
          isUnderline = true;
        }

        if (isUnderline || isStrike) {
          sliceStyle = sliceStyle.copyWith(
            decoration: (isUnderline && isStrike)
                ? TextDecoration.combine([
                    TextDecoration.underline,
                    TextDecoration.lineThrough,
                  ])
                : (isUnderline
                    ? TextDecoration.underline
                    : TextDecoration.lineThrough),
            decorationColor: sliceStyle.color,
            decorationThickness: isUnderline ? (hasLink ? 1.3 : 1.5) : null,
          );
        }

        if (isCode) {
          sliceStyle = sliceStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: (rangeBaseStyle.fontSize ?? _kMessageFontSize) * 0.95,
          );
        }

        if (isSpoilerHidden) {
          sliceStyle = sliceStyle.copyWith(
            color: Colors.transparent,
            decorationColor: Colors.transparent,
          );
        }

        GestureRecognizer? recognizer;
        if (!isSpoilerHidden) {
          if (hasLink) {
            final targetUrl = linkUrl;
            recognizer = _createTapRecognizer(() => _handleLinkTap(targetUrl));
          } else if (isCode) {
            recognizer = _createTapRecognizer(() => _handleCodeCopy(sliceText));
          }
        }

        if (isCode) {
          children.add(TextSpan(
            text: sliceText,
            style: sliceStyle,
            recognizer: recognizer,
          ));
        } else {
          children.add(EmojiUtils.buildEmojiTextSpan(
            sliceText,
            style: sliceStyle,
            recognizer: recognizer,
          ));
        }

        i++;
      }

      return TextSpan(style: rangeBaseStyle, children: children);
    }

    if (spoilerRanges.isEmpty) {
      return Text.rich(
        buildSpanTree(const <int>{}),
        strutStyle: strutStyle,
      );
    }

    final particleColor = rangeBaseStyle.color ??
        (widget.isDark ? Colors.white : Colors.black);

    return SpoilerTextWidget.inlineHost(
      inlineRanges: spoilerRanges,
      particleColor: particleColor,
      stateKey: 'inline_${rangeStart}_$rangeEnd',
      inlineBuilder: (context, richTextKey, hiddenSpoilerIds) {
        return Text.rich(
          buildSpanTree(hiddenSpoilerIds),
          key: richTextKey,
          strutStyle: strutStyle,
        );
      },
    );
  }

  Widget _buildBlockSegmentWidget(_MessageSegment seg) {
    final block = seg.blockEntity!;
    final bStart = seg.start;
    final bEnd = seg.end;
    final blockText = widget.cleanText.substring(bStart, bEnd);

    if (block.type == 'pre') {
      final codeWidget = CodeBlockWidget(
        code: blockText.trim(),
        language: block.language,
        isDark: widget.isDark,
        isMe: widget.isMe,
        preset: widget.nameColorPreset,
        stripStyle: widget.replyStripStyle,
      );
      final bool coveredBySpoiler = widget.entities.any(
        (e) =>
            e.type == 'spoiler' &&
            e.offset <= bStart &&
            (e.offset + e.length) >= bEnd,
      );
      if (coveredBySpoiler) {
        return SpoilerTextWidget(
          textStyle: widget.baseStyle,
          stateKey: 'pre_spoiler_${bStart}_$bEnd',
          child: codeWidget,
        );
      }
      return codeWidget;
    }

    if (block.type == 'latex_block') {
      final formula = block.language ?? blockText;
      return _buildLatexWidget(
        formula,
        widget.baseStyle,
        isDisplayMode: true,
      );
    }

    if (TextMessageWidget._isQuoteType(block.type)) {
      final bool isCollapsible = block.collapsed == true ||
          block.type == 'collapse' ||
          block.type == 'expandable_blockquote';

      final profileTheme = context.read<ProfileThemeProvider?>();
      final effectivePreset = widget.nameColorPreset ??
          profileTheme?.currentNameColorPreset ??
          NameColorPresets.red;
      final cardBgColor =
          effectivePreset.getOpaqueCardBackgroundColor(widget.isDark);
      final readableQuoteTextColor =
          NameColorPreset.resolveReadableTextColor(cardBgColor);
      final readableQuoteLinkColor = NameColorPreset.resolveReadableAccentColor(
        cardBgColor,
        widget.linkColor,
      );

      final quoteTextStyle = TextStyle(
        fontSize: 14,
        color: readableQuoteTextColor,
        height: 1.22,
      );

      // Check if there are any inline entities overlapping this blockquote
      final hasInnerEntities = widget.entities.any((e) {
        if (TextMessageWidget._isBlockType(e.type)) return false;
        final eEnd = e.offset + e.length;
        return e.offset < bEnd && eEnd > bStart;
      });

      Widget? formattedChild;
      if (hasInnerEntities || EmojiUtils.hasPotentialEmoji(blockText)) {
        formattedChild = _buildInlineRangeWidget(
          fullText: widget.cleanText,
          rangeStart: bStart,
          rangeEnd: bEnd,
          allEntities: widget.entities,
          rangeBaseStyle: quoteTextStyle,
          rangeLinkColor: readableQuoteLinkColor,
        );
      }

      return CollapsibleBlockquoteWidget(
        text: blockText,
        isCollapsible: isCollapsible,
        initialExpanded: false,
        isDark: widget.isDark,
        isMe: widget.isMe,
        preset: widget.nameColorPreset,
        stripStyle: widget.replyStripStyle,
        stateKey: 'quote_${bStart}_$bEnd',
        child: formattedChild,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final segments = _splitIntoSegments(widget.cleanText, widget.entities);

    if (segments.length == 1) {
      final seg = segments.first;
      if (seg.isBlock) {
        return _buildBlockSegmentWidget(seg);
      }
      return _buildInlineRangeWidget(
        fullText: widget.cleanText,
        rangeStart: seg.start,
        rangeEnd: seg.end,
        allEntities: widget.entities,
        rangeBaseStyle: widget.baseStyle,
        rangeLinkColor: widget.linkColor,
      );
    }

    final children = <Widget>[];
    for (final seg in segments) {
      if (seg.isBlock) {
        children.add(_buildBlockSegmentWidget(seg));
      } else {
        children.add(
          _buildInlineRangeWidget(
            fullText: widget.cleanText,
            rangeStart: seg.start,
            rangeEnd: seg.end,
            allEntities: widget.entities,
            rangeBaseStyle: widget.baseStyle,
            rangeLinkColor: widget.linkColor,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
