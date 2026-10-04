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

/// Custom block syntax for collapsible blockquotes: lines starting with **>
class CollapsibleBlockquoteBlockSyntax extends md.BlockSyntax {
  static final RegExp _pattern = RegExp(r'^[ ]{0,3}\*\*>[ ]?(.*)$');

  @override
  RegExp get pattern => _pattern;

  const CollapsibleBlockquoteBlockSyntax();

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) {
    final childLines = <md.Line>[];

    while (!parser.isDone) {
      final currentLine = parser.current;
      final match = pattern.firstMatch(currentLine.content);
      if (match != null) {
        final markerStart = currentLine.content.indexOf('**>');
        int markerEnd = markerStart + 3;
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
    final children = md.BlockParser(childLines, parser.document).parseLines(
      parentSyntax: this,
    );
    final element = md.Element('blockquote', children);
    element.attributes['collapsed'] = 'true';
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

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rawText = element.textContent.trim();
    if (rawText.isEmpty) return null;

    final bool isCollapsible = element.attributes['collapsed'] == 'true' ||
        rawText.startsWith('collapse:') ||
        rawText.startsWith('**>');

    final text = rawText
        .replaceFirst(RegExp(r'^(?:collapse:|\*\*>\s?)\s*'), '');

    return CollapsibleBlockquoteWidget(
      text: text,
      isCollapsible: isCollapsible,
      initialExpanded: false,
      isDark: isDark,
      isMe: isMe,
      preset: preset,
      stripStyle: stripStyle,
    );
  }
}

/// Builder for LaTeX formulas using [Math].
class MathElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (text.isEmpty) return null;

    bool isDisplayMode = text.startsWith(r'$$') && text.endsWith(r'$$');
    final math = isDisplayMode
        ? text.substring(2, text.length - 2).trim()
        : text.substring(1, text.length - 1).trim();

    return Math.tex(
      math,
      mathStyle: isDisplayMode ? MathStyle.display : MathStyle.text,
      textStyle: preferredStyle?.copyWith(
        color: Colors.teal,
        fontStyle: FontStyle.italic,
      ),
      onErrorFallback: (err) => Text(
        text,
        style: const TextStyle(color: Colors.red),
      ),
    );
  }
}

/// Custom syntax for LaTeX formulas: $...$ and $$...$$
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'(\$\$[\s\S]*?\$\$)|(\$[\s\S]*?\$)');

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
          fontFamily: 'AppleEmoji',
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

  static final RegExp _markdownIndicator = RegExp(r'[*_~`\[]');

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final effectiveStyle = preferredStyle ?? this.preferredStyle;
    final content = element.textContent;

    if (_markdownIndicator.hasMatch(content)) {
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
              UnderlineInlineSyntax(),
              EmojiInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
          styleSheet: MarkdownStyleSheet(
            p: effectiveStyle,
            pPadding: EdgeInsets.zero,
            strong: effectiveStyle?.copyWith(fontWeight: FontWeight.bold),
            em: effectiveStyle?.copyWith(fontStyle: FontStyle.italic),
            del: effectiveStyle?.copyWith(decoration: TextDecoration.lineThrough),
            code: effectiveStyle?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Colors.transparent,
            ),
          ),
          builders: {
            'underline': UnderlineElementBuilder(effectiveStyle),
            'emoji': EmojiElementBuilder(fontSize: effectiveStyle?.fontSize ?? _kMessageFontSize),
          },
        ),
      );
    }

    return SpoilerTextWidget.text(
      text: content,
      style: effectiveStyle,
    );
  }
}

/// Custom syntax for underline: __...__ or --...-- or <u>...</u>
class UnderlineInlineSyntax extends md.InlineSyntax {
  UnderlineInlineSyntax() : super(r'(?:__|\-\-|<u>)([\s\S]+?)(?:__|\-\-|</u>)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element.text('underline', match.group(1)!);
    parser.addNode(element);
    return true;
  }
}

/// Builder for underline text.
class UnderlineElementBuilder extends MarkdownElementBuilder {
  final TextStyle? baseStyle;

  UnderlineElementBuilder([this.baseStyle]);

  static final RegExp _markdownIndicator = RegExp(r'[*_~`\[]');

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final effectiveStyle = parentStyle ?? preferredStyle ?? baseStyle ?? DefaultTextStyle.of(context).style;
    final underlineStyle = effectiveStyle.copyWith(
      decoration: TextDecoration.combine([
        if (effectiveStyle.decoration != null && effectiveStyle.decoration != TextDecoration.none)
          effectiveStyle.decoration!,
        TextDecoration.underline,
      ]),
      decorationColor: effectiveStyle.color,
      decorationThickness: 1.5,
    );

    final content = element.textContent;
    if (_markdownIndicator.hasMatch(content)) {
      return MarkdownBody(
        data: content,
        selectable: false,
        shrinkWrap: true,
        softLineBreak: true,
        extensionSet: md.ExtensionSet(
          [],
          [
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
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final effectiveStyle = preferredStyle ?? baseStyle;
    final underlineStyle = (effectiveStyle ?? const TextStyle()).copyWith(
      decoration: TextDecoration.combine([
        if (effectiveStyle?.decoration != null && effectiveStyle!.decoration != TextDecoration.none)
          effectiveStyle.decoration!,
        TextDecoration.underline,
      ]),
      decorationColor: effectiveStyle?.color,
      decorationThickness: 1.5,
    );

    final content = element.textContent;
    if (_markdownIndicator.hasMatch(content)) {
      return MarkdownBody(
        data: content,
        selectable: false,
        shrinkWrap: true,
        softLineBreak: true,
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
        ),
      );
    }

    return Text(
      content,
      style: underlineStyle,
    );
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
  /// Content inside code blocks is left untouched.
  static String preserveWhitespace(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return '';

    // Split by code blocks: ```...``` or `...`
    final pattern = RegExp(r'(```[\s\S]*?```|`[^`\n]*?`)');
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
    // Inserting '\u00A0' on empty lines ensures exact visual blank line count.
    result = result.replaceAllMapped(RegExp(r'\n{2,}'), (match) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String markdownData;
    if (entities != null && entities!.isNotEmpty) {
      final effectiveEntities = <MessageEntity>[...entities!];
      // Auto-detect any raw URLs in clean text not covered by existing entities
      for (final match in EntityParser.urlRegex.allMatches(text)) {
        final url = match.group(0)!;
        final start = match.start;
        final len = url.length;
        final covered = effectiveEntities.any((e) =>
            e.offset <= start && (e.offset + e.length) >= (start + len));
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

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final linkColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoingLink ??
            (isDark ? const Color(0xFF7BE5DA) : const Color(0xFF007AFF)))
        : (themeExt?.palette.chatBubbleIncomingLink ??
            (isDark ? const Color(0xFF7BE5DA) : Theme.of(context).colorScheme.primary));

    final formattedData = preserveWhitespace(markdownData);

    return MarkdownBody(
      data: formattedData,
      selectable: false,
      shrinkWrap: true,
      softLineBreak: true, // Позволяет делать перенос строки одним нажатием Enter
      extensionSet: md.ExtensionSet(
        [
          const CollapsibleBlockquoteBlockSyntax(),
          ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        ],
        [
          UnderlineInlineSyntax(),
          MathInlineSyntax(),
          CheckboxInlineSyntax(),
          EmojiInlineSyntax(),
          SpoilerInlineSyntax(),
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        ],
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          fontSize: style?.fontSize ?? _kMessageFontSize,
          height: 1.4,
        ),
        pPadding: EdgeInsets.zero,
        blockSpacing: 0,
        listBulletPadding: const EdgeInsets.only(right: 4),
        a: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
          decorationThickness: 1.3,
          fontSize: style?.fontSize ?? _kMessageFontSize,
          height: 1.4,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: (style?.fontSize ?? _kMessageFontSize) * 0.95,
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
        'latex': MathElementBuilder(),
        'checkbox': CheckboxElementBuilder(),
        'emoji': EmojiElementBuilder(fontSize: style?.fontSize ?? _kMessageFontSize),
        'spoiler': SpoilerElementBuilder(style),
        'underline': UnderlineElementBuilder(style),
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

