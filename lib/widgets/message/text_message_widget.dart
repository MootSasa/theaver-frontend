import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../../models/name_color_preset.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/entity_parser.dart';
import 'code_block_widget.dart';
import 'collapsible_blockquote_widget.dart';
import 'spoiler_text_widget.dart';
import '../../screens/settings/theme_preview_screen.dart';
import '../../services/theav_theme_service.dart';

// --- НАСТРОЙКИ СТИЛЯ ТЕКСТОВОГО СООБЩЕНИЯ ---
/// Стандартный размер шрифта сообщений.
const double _kMessageFontSize = 17.0;
// --------------------------------------------

/// Builder for code blocks using [CodeBlockWidget].
class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isDark;
  final bool isMe;
  final NameColorPreset? preset;
  final ReplyStripStyle? stripStyle;

  CodeElementBuilder(
    this.context,
    this.isDark,
    this.isMe, {
    this.preset,
    this.stripStyle,
  });

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Check if this is a block code (has newline or language attribute from markdown parser)
    final bool isBlock = element.attributes['class'] != null || 
                         element.textContent.contains('\n');

    if (!isBlock) {
      // Inline code rendering - use textContent as-is (without backticks)
      final codeText = element.textContent;
      return GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: codeText));
          GlassToastService().show(context, 'Код скопирован', icon: Icons.check);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Text(
            codeText,
            style: preferredStyle?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.transparent,
            ) ?? TextStyle(
              fontFamily: 'monospace',
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      );
    }

    // Block code: extract language and strip backticks from content
    final language = element.attributes['class']?.replaceFirst('language-', '');
    
    // Strip leading and trailing backticks from code content
    // The markdown parser sometimes includes ``` in textContent
    String code = element.textContent;
    if (code.startsWith('```')) {
      code = code.substring(3);
    }
    if (code.endsWith('```')) {
      code = code.substring(0, code.length - 3);
    }
    // Also strip language identifier if it's on the first line
    if (language != null && code.startsWith(language)) {
      code = code.substring(language.length);
    }
    code = code.trim();

    return CodeBlockWidget(
      code: code,
      language: language,
      isDark: isDark,
      isMe: isMe,
      preset: preset,
      stripStyle: stripStyle,
    );
  }
}

/// Custom block syntax for multi-line or single-line display LaTeX blocks: $$...$$ or \[...\]
class MathBlockSyntax extends md.BlockSyntax {
  static final RegExp _openDollarPattern = RegExp(r'^[ ]{0,3}\$\$(.*)$');
  static final RegExp _openBracketPattern = RegExp(r'^[ ]{0,3}\\\[(.*)$');

  @override
  RegExp get pattern => RegExp(r'^[ ]{0,3}(?:\$\$|\\\[)');

  const MathBlockSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final firstLine = parser.current.content;
    final bool isBracket = firstLine.trimLeft().startsWith(r'\[');
    final String closeToken = isBracket ? r'\]' : r'$$';
    final RegExp openPattern = isBracket ? _openBracketPattern : _openDollarPattern;

    final match = openPattern.firstMatch(firstLine);
    final firstRest = match?.group(1) ?? '';

    // Check if closing token is on the same line
    final closeIdx = firstRest.indexOf(closeToken);
    if (closeIdx != -1 && firstRest.substring(closeIdx + closeToken.length).trim().isEmpty) {
      parser.advance();
      final element = md.Element('p', [md.Element.text('latex', firstLine.trim())]);
      return element;
    }

    final lines = <String>[firstLine];
    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      lines.add(line);
      parser.advance();
      if (line.contains(closeToken)) {
        break;
      }
    }

    final fullMath = lines.join('\n').trim();
    return md.Element('p', [md.Element.text('latex', fullMath)]);
  }
}

/// Custom block syntax for collapsible blockquotes: lines starting with **>
class CollapsibleBlockquoteBlockSyntax extends md.BlockSyntax {
  static final RegExp _pattern = RegExp(r'^[ ]{0,3}\*\*>[ ]?(.*)$');
  static final RegExp _continuationPattern =
      RegExp(r'^[ ]{0,3}(?:\*\*)?>[ ]?(.*)$');

  @override
  RegExp get pattern => _pattern;

  const CollapsibleBlockquoteBlockSyntax();

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) {
    final childLines = <md.Line>[];

    while (!parser.isDone) {
      final currentLine = parser.current;
      final activePattern =
          childLines.isEmpty ? _pattern : _continuationPattern;
      final match = activePattern.firstMatch(currentLine.content);
      if (match != null) {
        childLines.add(md.Line(match.group(1) ?? ''));
        parser.advance();
        continue;
      }
      break;
    }

    return childLines;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final childLines = parseChildLines(parser);
    final rawMarkdown = childLines.map((l) => l.content).join('\n');
    final children = md.BlockParser(childLines, parser.document).parseLines(
      parentSyntax: this,
    );
    final element = md.Element('blockquote', children);
    element.attributes['collapsed'] = 'true';
    element.attributes['raw_markdown'] = rawMarkdown;
    return element;
  }
}

/// Custom strict block syntax for standard blockquotes: lines starting with > (without lazy continuation)
class StrictBlockquoteBlockSyntax extends md.BlockSyntax {
  static final RegExp _pattern = RegExp(r'^[ ]{0,3}>[ ]?(.*)$');

  @override
  RegExp get pattern => _pattern;

  const StrictBlockquoteBlockSyntax();

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) {
    final childLines = <md.Line>[];

    while (!parser.isDone) {
      final currentLine = parser.current;
      final match = pattern.firstMatch(currentLine.content);
      if (match != null) {
        final markerStart = currentLine.content.indexOf('>');
        int markerEnd = markerStart + 1;
        if (currentLine.content.length > markerEnd &&
            (currentLine.content[markerEnd] == ' ' || currentLine.content[markerEnd] == '\t')) {
          markerEnd++;
        }
        childLines.add(md.Line(currentLine.content.substring(markerEnd)));
        parser.advance();
        continue;
      }
      break;
    }

    return childLines;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final childLines = parseChildLines(parser);
    final rawMarkdown = childLines.map((l) => l.content).join('\n');
    final children = md.BlockParser(childLines, parser.document).parseLines(
      parentSyntax: this,
    );
    final element = md.Element('blockquote', children);
    element.attributes['collapsed'] = 'false';
    element.attributes['raw_markdown'] = rawMarkdown;
    return element;
  }
}

/// Builder for Markdown blockquotes using [CollapsibleBlockquoteWidget].
class BlockquoteElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isDark;
  final bool isMe;
  final NameColorPreset? preset;
  final ReplyStripStyle? stripStyle;

  BlockquoteElementBuilder(
    this.context,
    this.isDark,
    this.isMe, {
    this.preset,
    this.stripStyle,
  });

  static final RegExp _richIndicator = RegExp(r'[*_~`\[$<|]|https?:\/\/|www\.');

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rawText = element.textContent.trim();
    if (rawText.isEmpty) return null;

    final bool isCollapsible = element.attributes['collapsed'] == 'true' ||
        rawText.startsWith('collapse:') ||
        rawText.startsWith('**>');

    final text = rawText
        .replaceFirst(RegExp(r'^(?:collapse:|\*\*>\s?)\s*'), '');

    final rawMarkdown = (element.attributes['raw_markdown'] ?? text)
        .trim()
        .replaceFirst(RegExp(r'^(?:collapse:|\*\*>\s?)\s*'), '');

    final cleanQuoteText = EntityParser.parseMarkdown(rawMarkdown).cleanText.trim();
    final effectivePlainText = cleanQuoteText.isNotEmpty ? cleanQuoteText : text;

    final quoteTextStyle = TextStyle(
      fontSize: 14,
      color: isDark
          ? const Color(0xFFE2E8F0)
          : const Color(0xFF1C2530),
      height: 1.35,
    );

    Widget? formattedChild;
    if (_richIndicator.hasMatch(rawMarkdown) || EmojiUtils.emojiRegex.hasMatch(rawMarkdown)) {
      final themeExt = Theme.of(context).extension<TheavThemeExtension>();
      final linkColor = isMe
          ? (themeExt?.palette.chatBubbleOutgoingLink ??
              (isDark ? const Color(0xFF7BE5DA) : const Color(0xFF007AFF)))
          : (themeExt?.palette.chatBubbleIncomingLink ??
              (isDark ? const Color(0xFF7BE5DA) : Theme.of(context).colorScheme.primary));

      formattedChild = MarkdownBody(
        data: rawMarkdown,
        selectable: false,
        shrinkWrap: true,
        softLineBreak: true,
        extensionSet: md.ExtensionSet(
          const [MathBlockSyntax()],
          [
            md.CodeSyntax(),
            MathInlineSyntax(),
            SpoilerInlineSyntax(),
            UnderlineInlineSyntax(),
            CheckboxInlineSyntax(),
            EmojiInlineSyntax(),
            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
          ],
        ),
        styleSheet: MarkdownStyleSheet(
          p: quoteTextStyle,
          pPadding: EdgeInsets.zero,
          blockSpacing: 0.0,
          strong: quoteTextStyle.copyWith(fontWeight: FontWeight.bold),
          em: quoteTextStyle.copyWith(fontStyle: FontStyle.italic),
          del: quoteTextStyle.copyWith(decoration: TextDecoration.lineThrough),
          a: quoteTextStyle.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          code: quoteTextStyle.copyWith(
            fontFamily: 'monospace',
            fontStyle: FontStyle.normal,
            backgroundColor: Colors.transparent,
          ),
        ),
        builders: {
          'code': CodeElementBuilder(
            context,
            isDark,
            isMe,
            preset: preset,
            stripStyle: stripStyle,
          ),
          'latex': MathElementBuilder(quoteTextStyle),
          'checkbox': CheckboxElementBuilder(),
          'emoji': EmojiElementBuilder(fontSize: 14),
          'spoiler': SpoilerElementBuilder(quoteTextStyle),
          'underline': UnderlineElementBuilder(quoteTextStyle),
        },
        onTapLink: (label, href, title) async {
          if (href != null && href.trim().isNotEmpty) {
            final normalized = EntityParser.normalizeUrl(href.trim());
            final uri = Uri.tryParse(normalized);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
      );
    }

    return CollapsibleBlockquoteWidget(
      text: effectivePlainText,
      isCollapsible: isCollapsible,
      initialExpanded: false,
      isDark: isDark,
      isMe: isMe,
      preset: preset,
      stripStyle: stripStyle,
      child: formattedChild,
    );
  }
}

/// Builder for LaTeX formulas using [Math].
class MathElementBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  MathElementBuilder([this.baseStyle]);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final effectiveStyle = parentStyle ?? preferredStyle ?? baseStyle ?? DefaultTextStyle.of(context).style;
    return _buildMath(element, effectiveStyle);
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final effectiveStyle = preferredStyle ?? baseStyle ?? const TextStyle(fontSize: _kMessageFontSize);
    return _buildMath(element, effectiveStyle);
  }

  Widget? _buildMath(md.Element element, TextStyle effectiveStyle) {
    final text = element.textContent.trim();
    if (text.isEmpty) return null;

    final bool isDoubleDollar = text.startsWith(r'$$') && text.endsWith(r'$$') && text.length >= 4;
    final bool isBracketDisplay = text.startsWith(r'\[') && text.endsWith(r'\]') && text.length >= 4;
    final bool isParenInline = text.startsWith(r'\(') && text.endsWith(r'\)') && text.length >= 4;
    final bool isDisplayMode = isDoubleDollar || isBracketDisplay;

    final String math;
    if (isDoubleDollar || isBracketDisplay || isParenInline) {
      math = text.substring(2, text.length - 2).trim();
    } else if (text.startsWith(r'$') && text.endsWith(r'$') && text.length >= 2) {
      math = text.substring(1, text.length - 1).trim();
    } else {
      math = text;
    }

    if (math.isEmpty) return Text(text, style: effectiveStyle);

    final mathTextStyle = effectiveStyle.copyWith(
      fontStyle: FontStyle.normal,
    );

    final Widget mathWidget = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Math.tex(
        math,
        mathStyle: isDisplayMode ? MathStyle.display : MathStyle.text,
        textStyle: mathTextStyle,
        onErrorFallback: (err) => Text(
          text,
          style: effectiveStyle.copyWith(
            color: Colors.redAccent,
            fontFamily: 'monospace',
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
}

/// Custom syntax for LaTeX formulas: $$...$$, \[...\], \(...\), and $...$
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax()
      : super(
          r'(\$\$[\s\S]+?\$\$)|(\\\[[\s\S]+?\\\])|(\\\([\s\S]+?\\\))|((?<!\\|\$)\$(?!\$|\s)(?:\\.|[^\\\n\$])+?(?<!\s|\\)\$(?!\$|\d))',
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('latex', match.group(0)!);
    parser.addNode(element);
    return true;
  }
}

/// Custom syntax for inline checkboxes: [ ] and [x]
class CheckboxInlineSyntax extends md.InlineSyntax {
  CheckboxInlineSyntax() : super(r'(\[ \]|\[x\])');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final isChecked = match.group(0)!.contains('x');
    final element = md.Element.text('checkbox', isChecked ? 'checked' : 'unchecked');
    parser.addNode(element);
    return true;
  }
}

/// Custom syntax for Apple Emojis
class EmojiInlineSyntax extends md.InlineSyntax {
  EmojiInlineSyntax() : super(EmojiUtils.emojiRegex.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('emoji', match.group(0)!);
    parser.addNode(element);
    return true;
  }
}

/// Builder for inline checkboxes using real Material Checkbox widget.
class CheckboxElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final isChecked = element.textContent == 'checked';
    
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Checkbox(
          value: isChecked,
          onChanged: null,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// Builder for Apple Emojis using CDN.
class EmojiElementBuilder extends MarkdownElementBuilder {
  final double fontSize;
  EmojiElementBuilder({required this.fontSize});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // We now use the font fallback, but we can still use images for better look in chat
    // or just let the font handle it. Let's keep images for chat bubbles 
    // as they look better (retina quality) and use font for input.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: EmojiUtils.appleEmoji(
        element.textContent,
        size: fontSize * 1,
        fallbackStyle: preferredStyle?.copyWith(
          fontFamily: EmojiUtils.effectiveFontFamily,
        ),
      ),
    );
  }
}

/// Custom syntax for spoilers: ||...||
class SpoilerInlineSyntax extends md.InlineSyntax {
  SpoilerInlineSyntax() : super(r'\|\|((?:[^|\n]|\|(?!\|))+?)\|\|');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('spoiler', match.group(1)!);
    parser.addNode(element);
    return true;
  }
}

/// Builder for spoilers using [SpoilerTextWidget].
class SpoilerElementBuilder extends MarkdownElementBuilder {
  final TextStyle? preferredStyle;

  SpoilerElementBuilder(this.preferredStyle);

  static final RegExp _markdownIndicator = RegExp(r'[*_~`\[$<]');

  TextStyle _resolveStyle(TextStyle? preferred, TextStyle? parent) {
    TextStyle resolved = preferredStyle ?? const TextStyle();
    if (preferred != null) resolved = resolved.merge(preferred);
    if (parent != null) {
      final combinedDecoration = (resolved.decoration != null &&
              resolved.decoration != TextDecoration.none &&
              parent.decoration != null &&
              parent.decoration != TextDecoration.none)
          ? TextDecoration.combine([resolved.decoration!, parent.decoration!])
          : (parent.decoration ?? resolved.decoration);
      resolved = resolved.merge(parent).copyWith(decoration: combinedDecoration);
    }
    return resolved;
  }

  Widget _buildSpoiler(String content, TextStyle effectiveStyle) {
    if (_markdownIndicator.hasMatch(content) || EmojiUtils.emojiRegex.hasMatch(content)) {
      return SpoilerTextWidget(
        textStyle: effectiveStyle,
        child: MarkdownBody(
          data: content,
          selectable: false,
          shrinkWrap: true,
          softLineBreak: true,
          extensionSet: md.ExtensionSet(
            [],
            [
              md.CodeSyntax(),
              MathInlineSyntax(),
              UnderlineInlineSyntax(),
              EmojiInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
          styleSheet: MarkdownStyleSheet(
            p: effectiveStyle,
            pPadding: EdgeInsets.zero,
            strong: effectiveStyle.copyWith(fontWeight: FontWeight.bold),
            em: effectiveStyle.copyWith(fontStyle: FontStyle.italic),
            del: effectiveStyle.copyWith(
              decoration: effectiveStyle.decoration != null &&
                      effectiveStyle.decoration != TextDecoration.none
                  ? TextDecoration.combine([
                      effectiveStyle.decoration!,
                      TextDecoration.lineThrough,
                    ])
                  : TextDecoration.lineThrough,
            ),
            code: effectiveStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.transparent,
            ),
          ),
          builders: {
            'latex': MathElementBuilder(effectiveStyle),
            'underline': UnderlineElementBuilder(effectiveStyle),
            'emoji': EmojiElementBuilder(fontSize: effectiveStyle.fontSize ?? _kMessageFontSize),
          },
        ),
      );
    }

    return SpoilerTextWidget.text(
      text: content,
      style: effectiveStyle,
    );
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final effectiveStyle = _resolveStyle(preferredStyle, parentStyle);
    return _buildSpoiler(element.textContent, effectiveStyle);
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final effectiveStyle = _resolveStyle(preferredStyle, null);
    return _buildSpoiler(element.textContent, effectiveStyle);
  }
}

/// Custom syntax for underline: __...__ or <u>...</u>
class UnderlineInlineSyntax extends md.InlineSyntax {
  UnderlineInlineSyntax()
      : super(
          r'(?:(?<![a-zA-Z0-9_])__(?!\s|_)((?:(?!__)[^\n])+?)(?<!\s|_)__(?![a-zA-Z0-9_])|<u>([\s\S]+?)<\/u>)',
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1) ?? match.group(2) ?? '';
    final element = md.Element.text('underline', content);
    parser.addNode(element);
    return true;
  }
}

/// Builder for underline text.
class UnderlineElementBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  UnderlineElementBuilder([this.baseStyle]);

  static final RegExp _markdownIndicator = RegExp(r'[*_~`\[$<|]');

  TextStyle _resolveUnderlineStyle(TextStyle? preferred, TextStyle? parent, [TextStyle? fallback]) {
    TextStyle effective = baseStyle ?? fallback ?? const TextStyle();
    if (preferred != null) effective = effective.merge(preferred);
    if (parent != null) effective = effective.merge(parent);
    return effective.copyWith(
      decoration: TextDecoration.combine([
        if (effective.decoration != null && effective.decoration != TextDecoration.none)
          effective.decoration!,
        TextDecoration.underline,
      ]),
      decorationColor: effective.color,
      decorationThickness: 1.5,
    );
  }

  Widget _buildUnderline(String content, TextStyle underlineStyle) {
    if (_markdownIndicator.hasMatch(content) || EmojiUtils.emojiRegex.hasMatch(content)) {
      return MarkdownBody(
        data: content,
        selectable: false,
        shrinkWrap: true,
        softLineBreak: true,
        extensionSet: md.ExtensionSet(
          [],
          [
            md.CodeSyntax(),
            MathInlineSyntax(),
            SpoilerInlineSyntax(),
            UnderlineInlineSyntax(),
            EmojiInlineSyntax(),
            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
          ],
        ),
        styleSheet: MarkdownStyleSheet(
          p: underlineStyle,
          pPadding: EdgeInsets.zero,
          strong: underlineStyle.copyWith(fontWeight: FontWeight.bold),
          em: underlineStyle.copyWith(fontStyle: FontStyle.italic),
          del: underlineStyle.copyWith(
            decoration: TextDecoration.combine([
              TextDecoration.underline,
              TextDecoration.lineThrough,
            ]),
          ),
          code: underlineStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Colors.transparent,
          ),
        ),
        builders: {
          'latex': MathElementBuilder(underlineStyle),
          'spoiler': SpoilerElementBuilder(underlineStyle),
          'emoji': EmojiElementBuilder(fontSize: underlineStyle.fontSize ?? _kMessageFontSize),
        },
      );
    }

    return Text(
      content,
      style: underlineStyle,
    );
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final underlineStyle = _resolveUnderlineStyle(
      preferredStyle,
      parentStyle,
      DefaultTextStyle.of(context).style,
    );
    return _buildUnderline(element.textContent, underlineStyle);
  }

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final underlineStyle = _resolveUnderlineStyle(preferredStyle, null);
    return _buildUnderline(element.textContent, underlineStyle);
  }
}

/// Виджет для отображения текстового сообщения с Markdown-подсветкой.
///
/// Использует [flutter_markdown] для рендеринга и [CodeBlockWidget] для блоков кода.
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

    // Split by code blocks (```...```, `...`) and LaTeX formulas ($$...$$, \[...\], \(...\), $...$)
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
    // 1. Consecutive spaces (>= 2):
    // CommonMark collapses consecutive ASCII spaces. We alternate space and non-breaking space (\u00A0)
    // so every space is preserved with standard font width.
    var result = text.replaceAllMapped(RegExp(r' {2,}'), (match) {
      final len = match.group(0)!.length;
      final sb = StringBuffer();
      for (int i = 0; i < len; i++) {
        sb.write(i % 2 == 1 ? '\u00A0' : ' ');
      }
      return sb.toString();
    });

    // 2. Multiple newlines (>= 2):
    // With blockSpacing: 0, consecutive newlines would otherwise collapse without empty lines.
    // Inserting '\u00A0' on empty lines ensures exact visual blank line count,
    // except directly before a Markdown table row starting with '|'.
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

  static final RegExp _markdownIndicator = RegExp(r'[*_~`\[\]#>$|\\:]');
  static final Map<int, String> _formattedDataCache = {};
  static final md.ExtensionSet _kExtensionSet = md.ExtensionSet(
    [
      const MathBlockSyntax(),
      const CollapsibleBlockquoteBlockSyntax(),
      const StrictBlockquoteBlockSyntax(),
      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    ],
    [
      md.CodeSyntax(),
      MathInlineSyntax(),
      SpoilerInlineSyntax(),
      UnderlineInlineSyntax(),
      CheckboxInlineSyntax(),
      EmojiInlineSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
      fontSize: style?.fontSize ?? _kMessageFontSize,
      height: 1.4,
    );

    final bool hasEntities = entities != null && entities!.isNotEmpty;
    final bool hasLinks = text.contains('http://') || text.contains('https://') || text.contains('www.');

    // Fast-path: Plain text without markdown, entities, or URLs renders instantly without AST parser
    if (!hasEntities && !hasLinks && !_markdownIndicator.hasMatch(text)) {
      if (EmojiUtils.emojiRegex.hasMatch(text)) {
        return Text.rich(
          EmojiUtils.buildEmojiTextSpan(
            text,
            style: effectiveStyle ?? const TextStyle(),
          ),
        );
      }
      return Text(
        text,
        style: effectiveStyle,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final int entitiesHash = hasEntities
        ? Object.hashAll(
            entities!.map((e) => Object.hash(e.type, e.offset, e.length, e.url, e.language, e.collapsed)),
          )
        : 0;
    final int cacheKey = Object.hash(2, text, entitiesHash);
    String? formattedData = _formattedDataCache[cacheKey];
    if (formattedData == null) {
      final String markdownData;
      if (hasEntities) {
        final effectiveEntities = <MessageEntity>[...entities!];
        for (final match in EntityParser.urlRegex.allMatches(text)) {
          final url = match.group(0)!;
          final start = match.start;
          final len = url.length;
          final covered = effectiveEntities.any((e) =>
              (e.type == 'text_link' ||
                  e.type == 'link' ||
                  e.type == 'url' ||
                  e.type == 'pre' ||
                  e.type == 'code') &&
              e.offset <= start &&
              (e.offset + e.length) >= (start + len));
          if (!covered) {
            effectiveEntities.add(MessageEntity(
              type: 'url',
              offset: start,
              length: len,
              url: url,
            ));
          }
        }
        markdownData = EntityParser.toMarkdown(text, effectiveEntities);
      } else {
        markdownData = text;
      }
      formattedData = preserveWhitespace(markdownData);
      if (_formattedDataCache.length > 500) {
        _formattedDataCache.clear();
      }
      _formattedDataCache[cacheKey] = formattedData;
    }

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final linkColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoingLink ??
            (isDark ? const Color(0xFF7BE5DA) : const Color(0xFF007AFF)))
        : (themeExt?.palette.chatBubbleIncomingLink ??
            (isDark ? const Color(0xFF7BE5DA) : Theme.of(context).colorScheme.primary));

    final baseFontSize = style?.fontSize ?? _kMessageFontSize;

    return MarkdownBody(
      data: formattedData,
      selectable: false,
      shrinkWrap: true,
      softLineBreak: true, // Позволяет делать перенос строки одним нажатием Enter
      extensionSet: _kExtensionSet,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: effectiveStyle,
        pPadding: EdgeInsets.zero,
        blockSpacing: 0,
        strong: effectiveStyle?.copyWith(fontWeight: FontWeight.bold),
        em: effectiveStyle?.copyWith(fontStyle: FontStyle.italic),
        del: effectiveStyle?.copyWith(decoration: TextDecoration.lineThrough),
        h1: effectiveStyle?.copyWith(fontSize: baseFontSize * 1.35, fontWeight: FontWeight.bold),
        h2: effectiveStyle?.copyWith(fontSize: baseFontSize * 1.25, fontWeight: FontWeight.bold),
        h3: effectiveStyle?.copyWith(fontSize: baseFontSize * 1.15, fontWeight: FontWeight.bold),
        h4: effectiveStyle?.copyWith(fontSize: baseFontSize * 1.08, fontWeight: FontWeight.w600),
        h5: effectiveStyle?.copyWith(fontSize: baseFontSize, fontWeight: FontWeight.w600),
        h6: effectiveStyle?.copyWith(fontSize: baseFontSize * 0.95, fontWeight: FontWeight.w600),
        listBullet: effectiveStyle,
        listBulletPadding: const EdgeInsets.only(right: 4),
        tableHead: effectiveStyle?.copyWith(fontWeight: FontWeight.bold),
        tableBody: effectiveStyle,
        a: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
          decorationThickness: 1.3,
          fontSize: baseFontSize,
          height: 1.4,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: baseFontSize * 0.95,
          height: 1.4,
          color: (style ?? Theme.of(context).textTheme.bodyMedium)?.color,
          backgroundColor: Colors.transparent,
        ),
        codeblockDecoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        codeblockPadding: EdgeInsets.zero,
        blockquoteDecoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        blockquotePadding: EdgeInsets.zero,
      ),
      builders: {
        'code': CodeElementBuilder(
          context,
          isDark,
          isMe,
          preset: nameColorPreset,
          stripStyle: replyStripStyle,
        ),
        'blockquote': BlockquoteElementBuilder(
          context,
          isDark,
          isMe,
          preset: nameColorPreset,
          stripStyle: replyStripStyle,
        ),
        'latex': MathElementBuilder(effectiveStyle),
        'checkbox': CheckboxElementBuilder(),
        'emoji': EmojiElementBuilder(fontSize: baseFontSize),
        'spoiler': SpoilerElementBuilder(effectiveStyle),
        'underline': UnderlineElementBuilder(effectiveStyle),
      },
      onTapLink: (text, href, title) async {
        if (href != null && href.trim().isNotEmpty) {
          final normalized = EntityParser.normalizeUrl(href.trim());
          final themeCode = TheavThemeService.extractThemeCode(normalized);
          if (themeCode != null) {
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
      },
    );
  }
}

