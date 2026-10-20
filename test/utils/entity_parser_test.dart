import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:theaver/utils/entity_parser.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/chat/rich_text_editing_controller.dart';
import 'package:theaver/widgets/message/text_message_widget.dart';

void main() {
  group('EntityParser Markdown Parsing', () {
    test('parses bold syntax', () {
      final res = EntityParser.parseMarkdown('Hello **bold text** world');
      expect(res.cleanText, 'Hello bold text world');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'bold');
      expect(res.entities.first.offset, 6);
      expect(res.entities.first.length, 'bold text'.length);
    });

    test('parses italic syntax', () {
      final res = EntityParser.parseMarkdown('Hello *italic* and _italic2_');
      expect(res.cleanText, 'Hello italic and italic2');
      expect(res.entities.length, 2);
      expect(res.entities[0].type, 'italic');
      expect(res.entities[0].offset, 6);
      expect(res.entities[0].length, 'italic'.length);
      expect(res.entities[1].type, 'italic');
      expect(res.entities[1].offset, 17);
      expect(res.entities[1].length, 'italic2'.length);
    });

    test('parses strikethrough syntax', () {
      final res = EntityParser.parseMarkdown('~~strikethrough~~');
      expect(res.cleanText, 'strikethrough');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'strikethrough');
      expect(res.entities.first.offset, 0);
      expect(res.entities.first.length, 'strikethrough'.length);
    });

    test('parses underline syntax', () {
      final res = EntityParser.parseMarkdown('__underlined text__');
      expect(res.cleanText, 'underlined text');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'underline');
      expect(res.entities.first.offset, 0);
      expect(res.entities.first.length, 'underlined text'.length);
    });

    test('parses spoiler syntax', () {
      final res = EntityParser.parseMarkdown('Look at ||this secret|| now');
      expect(res.cleanText, 'Look at this secret now');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'spoiler');
      expect(res.entities.first.offset, 8);
      expect(res.entities.first.length, 'this secret'.length);
    });

    test('parses inline code syntax', () {
      final res = EntityParser.parseMarkdown('run `flutter test` here');
      expect(res.cleanText, 'run flutter test here');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'code');
      expect(res.entities.first.offset, 4);
      expect(res.entities.first.length, 'flutter test'.length);
    });

    test('parses pre / code block syntax with language', () {
      final res = EntityParser.parseMarkdown('```dart\nvoid main() {}\n```');
      expect(res.cleanText, 'void main() {}');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'pre');
      expect(res.entities.first.language, 'dart');
      expect(res.entities.first.offset, 0);
      expect(res.entities.first.length, 'void main() {}'.length);
    });

    test('parses blockquote syntax', () {
      final res = EntityParser.parseMarkdown('> This is a quote');
      expect(res.cleanText, 'This is a quote');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'blockquote');
      expect(res.entities.first.collapsed, false);
      expect(res.entities.first.offset, 0);
      expect(res.entities.first.length, 'This is a quote'.length);
    });

    test('parses collapsible blockquote syntax', () {
      final res = EntityParser.parseMarkdown('**> This is a collapsible quote');
      expect(res.cleanText, 'This is a collapsible quote');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'blockquote');
      expect(res.entities.first.collapsed, true);
    });

    test('parses text_link syntax', () {
      final res = EntityParser.parseMarkdown('Visit [MIPT](https://mipt.ru) today');
      expect(res.cleanText, 'Visit MIPT today');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'text_link');
      expect(res.entities.first.url, 'https://mipt.ru');
      expect(res.entities.first.offset, 6);
      expect(res.entities.first.length, 4);
    });

    test('parses standalone URL syntax', () {
      final res = EntityParser.parseMarkdown('Check https://example.com for info');
      expect(res.cleanText, 'Check https://example.com for info');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'url');
      expect(res.entities.first.url, 'https://example.com');
      expect(res.entities.first.offset, 6);
      expect(res.entities.first.length, 'https://example.com'.length);
    });
  });

  group('EntityParser UTF-16 Offset Handling', () {
    test('handles emoji surrogate pairs correctly in offsets', () {
      // 🚀 is 2 UTF-16 code units (surrogate pair)
      final res = EntityParser.parseMarkdown('🚀 **rocket**');
      expect(res.cleanText, '🚀 rocket');
      // '🚀 ' length in UTF-16 is 2 + 1 = 3
      expect(res.entities.first.offset, 3);
      expect(res.entities.first.length, 'rocket'.length);
    });
  });

  group('EntityParser toMarkdown', () {
    test('reconstructs markdown from plain text and entities', () {
      const text = 'Hello world spoiler';
      const entities = [
        MessageEntity(type: 'bold', offset: 0, length: 5),
        MessageEntity(type: 'spoiler', offset: 12, length: 7),
      ];

      final md = EntityParser.toMarkdown(text, entities);
      expect(md, '**Hello** world ||spoiler||');
    });

    test('reconstructs links and quotes', () {
      const text = 'Quote text';
      const entities = [
        MessageEntity(type: 'blockquote', offset: 0, length: 10, collapsed: true),
      ];

      final md = EntityParser.toMarkdown(text, entities);
      expect(md, '**> Quote text');
    });
  });

  group('EntityParser URL Extraction', () {
    test('extracts multiple URLs', () {
      final urls = EntityParser.extractUrls(
        'Go to https://flutter.dev and http://dart.dev now',
      );
      expect(urls, ['https://flutter.dev', 'http://dart.dev']);
    });

    test('strips trailing parenthesis from markdown links and text', () {
      final urls = EntityParser.extractUrls(
        'Visit [Google](https://google.com) or (https://example.com)',
      );
      expect(urls, contains('https://google.com'));
      expect(urls, contains('https://example.com'));
      for (final u in urls) {
        expect(u.endsWith(')'), isFalse);
      }
    });

    test('cleanUrl strips trailing punctuation but preserves balanced parentheses', () {
      expect(EntityParser.cleanUrl('https://example.com)'), 'https://example.com');
      expect(EntityParser.cleanUrl('https://example.com.'), 'https://example.com');
      expect(EntityParser.cleanUrl('https://example.com,'), 'https://example.com');
      expect(
        EntityParser.cleanUrl('https://en.wikipedia.org/wiki/Dart_(programming_language)'),
        'https://en.wikipedia.org/wiki/Dart_(programming_language)',
      );
    });
  });

  group('EntityParser applyFormatting', () {
    test('wraps selected text with bold markdown', () {
      final controller = TextEditingController(text: 'Hello world');
      controller.selection = const TextSelection(baseOffset: 6, extentOffset: 11);

      EntityParser.applyFormatting(controller: controller, formatType: 'bold');
      expect(controller.text, 'Hello **world**');
    });

    test('inserts spoiler markers when nothing is selected', () {
      final controller = TextEditingController(text: 'Hello');
      controller.selection = const TextSelection.collapsed(offset: 5);

      EntityParser.applyFormatting(controller: controller, formatType: 'spoiler');
      expect(controller.text, 'Hello||||');
      expect(controller.selection.baseOffset, 7);
    });
  });

  group('RichTextEditingController Delimiter-Free Formatting', () {
    test('formats selection without inserting raw delimiter characters', () {
      final ctrl = RichTextEditingController(text: 'Hello secret world');
      ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 12); // 'secret'

      ctrl.applyFormat('spoiler');

      // Text remains clean! No || inserted!
      expect(ctrl.text, 'Hello secret world');
      expect(ctrl.cleanText, 'Hello secret world');
      expect(ctrl.entities.length, 1);
      expect(ctrl.entities.first.type, 'spoiler');
      expect(ctrl.entities.first.offset, 6);
      expect(ctrl.entities.first.length, 6);
    });

    test('toggles active format when nothing is selected and changes cursor mode', () {
      final ctrl = RichTextEditingController(text: 'Hello');
      ctrl.selection = const TextSelection.collapsed(offset: 5);

      // Tapping spoiler without selection toggles activeFormat, no characters inserted
      ctrl.applyFormat('spoiler');
      expect(ctrl.activeFormat, 'spoiler');
      expect(ctrl.text, 'Hello'); // No |||| added!

      // Typing with active format attaches spoiler entity
      ctrl.value = const TextEditingValue(
        text: 'Hello hidden',
        selection: TextSelection.collapsed(offset: 12),
      );

      expect(ctrl.cleanText, 'Hello hidden');
      expect(ctrl.entities.length, 1);
      expect(ctrl.entities.first.type, 'spoiler');
      expect(ctrl.entities.first.offset, 5);
      expect(ctrl.entities.first.length, 7);
    });

    test('isCursorItalic detects italic mode and cursor inside italic spans', () {
      final ctrl = RichTextEditingController(text: 'Hello italic world');
      expect(ctrl.isCursorItalic, isFalse);

      // Active format set to italic
      ctrl.activeFormat = 'italic';
      expect(ctrl.isCursorItalic, isTrue);

      ctrl.activeFormat = null;
      expect(ctrl.isCursorItalic, isFalse);

      // Format 'italic' on word 'italic' (offset 6 to 12)
      ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 12);
      ctrl.applyFormat('italic');

      // Cursor inside italic text (e.g. offset 8)
      ctrl.selection = const TextSelection.collapsed(offset: 8);
      expect(ctrl.isCursorItalic, isTrue);

      // Cursor outside italic text (e.g. offset 2)
      ctrl.selection = const TextSelection.collapsed(offset: 2);
      expect(ctrl.isCursorItalic, isFalse);
    });

    testWidgets('underline formatting applies TextDecoration.underline in buildTextSpan', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            final ctrl = RichTextEditingController(text: 'Hello underline text');
            ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 15);
            ctrl.applyFormat('underline');

            expect(ctrl.spans.length, 1);
            expect(ctrl.spans.first.type, 'underline');

            final span = ctrl.buildTextSpan(context: context, withComposing: false);
            expect(span.children, isNotNull);
            final underlineChild = span.children![1] as TextSpan;
            expect(underlineChild.text, 'underline');
            expect(underlineChild.style?.decoration, TextDecoration.underline);

            return const SizedBox.shrink();
          },
        ),
      ));
    });

    test('normalizeUrl prepends https:// when scheme is omitted', () {
      expect(EntityParser.normalizeUrl('google.com'), 'https://google.com');
      expect(EntityParser.normalizeUrl('www.github.com/flutter'), 'https://www.github.com/flutter');
      expect(EntityParser.normalizeUrl('http://insecure.site'), 'http://insecure.site');
      expect(EntityParser.normalizeUrl('https://secure.site'), 'https://secure.site');
    });

    test('extractUrls detects domains without http/https prefix', () {
      final urls = EntityParser.extractUrls('Check out google.com and www.github.com');
      expect(urls, contains('https://google.com'));
      expect(urls, contains('https://www.github.com'));
    });

    test('toMarkdown converts url and text_link entities into clickable markdown links', () {
      const text = 'Visit Google or click here';
      const entities = [
        MessageEntity(type: 'url', offset: 6, length: 6, url: 'google.com'),
        MessageEntity(type: 'text_link', offset: 16, length: 10, url: 'https://example.com'),
      ];
      final md = EntityParser.toMarkdown(text, entities);
      expect(md, 'Visit [Google](https://google.com) or [click here](https://example.com)');
    });

    test('RichTextEditingController loadMessage loads clean text and spans', () {
      final ctrl = RichTextEditingController();
      const text = 'Visit Google site';
      const entities = [
        MessageEntity(type: 'text_link', offset: 6, length: 6, url: 'https://google.com'),
      ];
      ctrl.loadMessage(text, entities);
      expect(ctrl.text, 'Visit Google site');
      expect(ctrl.spans.length, 1);
      expect(ctrl.spans.first.type, 'text_link');
      expect(ctrl.spans.first.url, 'https://google.com');
      expect(ctrl.spans.first.start, 6);
      expect(ctrl.spans.first.end, 12);
    });

    test('applyLinkToSelection and removeLinkFromSelection edit links properly', () {
      final ctrl = RichTextEditingController(text: 'Visit Google site');
      ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 12);
      ctrl.applyLinkToSelection('google.com');
      expect(ctrl.spans.length, 1);
      expect(ctrl.spans.first.url, 'https://google.com');

      // Edit the link URL on the same range
      ctrl.applyLinkToSelection('https://google.org', start: 6, end: 12);
      expect(ctrl.spans.length, 1);
      expect(ctrl.spans.first.url, 'https://google.org');

      // Remove the link
      ctrl.removeLinkFromSelection(start: 6, end: 12);
      expect(ctrl.spans.isEmpty, isTrue);
      expect(ctrl.text, 'Visit Google site');
    });

    test('RichTextEditingController entities detects raw URLs', () {
      final ctrl = RichTextEditingController(text: 'Check google.com');
      final entities = ctrl.entities;
      expect(entities.any((e) => e.type == 'url' && e.url == 'google.com'), isTrue);
    });

    test('RichTextEditingController cleanText returns parsed text when typing markdown directly', () {
      final ctrl = RichTextEditingController(text: 'Hello **world**');
      expect(ctrl.text, 'Hello **world**');
      expect(ctrl.cleanText, 'Hello world');
      expect(ctrl.entities.length, 1);
      expect(ctrl.entities.first.type, 'bold');
      expect(ctrl.entities.first.offset, 6);
      expect(ctrl.entities.first.length, 5);
    });

    testWidgets('monospace code has transparent background in RichTextEditingController buildTextSpan', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            final ctrl = RichTextEditingController(text: 'Hello code text');
            ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 10);
            ctrl.applyFormat('code');

            final span = ctrl.buildTextSpan(context: context, withComposing: false);
            final codeChild = span.children![1] as TextSpan;
            expect(codeChild.text, 'code');
            expect(codeChild.style?.fontFamily, 'monospace');
            expect(codeChild.style?.backgroundColor, isNull);

            return const SizedBox.shrink();
          },
        ),
      ));
    });
  });

  group('EntityParser Advanced & Nested Formatting', () {
    test('parses nested bold inside spoiler', () {
      final res = EntityParser.parseMarkdown('||**bold spoiler**||');
      expect(res.cleanText, 'bold spoiler');
      expect(res.entities.length, 2);
      expect(res.entities.any((e) => e.type == 'spoiler' && e.offset == 0 && e.length == 12), isTrue);
      expect(res.entities.any((e) => e.type == 'bold' && e.offset == 0 && e.length == 12), isTrue);
    });

    test('protects snake_case identifiers from italic parsing', () {
      final res = EntityParser.parseMarkdown('my_variable_name should not be italic');
      expect(res.cleanText, 'my_variable_name should not be italic');
      expect(res.entities.isEmpty, isTrue);
    });

    test('parses bare domain markdown link', () {
      final res = EntityParser.parseMarkdown('[Search](google.com)');
      expect(res.cleanText, 'Search');
      expect(res.entities.length, 1);
      expect(res.entities.first.type, 'text_link');
      expect(res.entities.first.url, 'https://google.com');
    });

    test('toMarkdown preserves order with multiple sequential and nested entities', () {
      const text = 'First Second Third';
      const entities = [
        MessageEntity(type: 'bold', offset: 0, length: 5), // First
        MessageEntity(type: 'spoiler', offset: 6, length: 6), // Second
        MessageEntity(type: 'italic', offset: 13, length: 5), // Third
      ];
      final md = EntityParser.toMarkdown(text, entities);
      expect(md, '**First** ||Second|| *Third*');
    });

    test('toMarkdown handles nested bold in spoiler', () {
      const text = 'secret';
      const entities = [
        MessageEntity(type: 'spoiler', offset: 0, length: 6),
        MessageEntity(type: 'bold', offset: 0, length: 6),
      ];
      final md = EntityParser.toMarkdown(text, entities);
      expect(md, '||**secret**||');
    });

    test('RichTextEditingController applies quote format as blockquote', () {
      final controller = RichTextEditingController(text: 'This is quoted');
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 14);
      controller.applyFormat('quote');

      expect(controller.entities.length, 1);
      expect(controller.entities.first.type, 'blockquote');
      expect(controller.toMarkdown(), '> This is quoted');
    });

    testWidgets('RichTextEditingController supports multiple mixed formats simultaneously', (tester) async {
      final controller = RichTextEditingController(text: 'Mixed style');
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 11);

      controller.applyFormat('bold');
      controller.applyFormat('italic');
      controller.applyFormat('underline');
      controller.applyFormat('spoiler');

      expect(controller.entities.length, 4);
      expect(controller.entities.any((e) => e.type == 'bold'), isTrue);
      expect(controller.entities.any((e) => e.type == 'italic'), isTrue);
      expect(controller.entities.any((e) => e.type == 'underline'), isTrue);
      expect(controller.entities.any((e) => e.type == 'spoiler'), isTrue);

      final md = controller.toMarkdown();
      expect(md.contains('**'), isTrue);
      expect(md.contains('*'), isTrue);
      expect(md.contains('__'), isTrue);
      expect(md.contains('||'), isTrue);
      expect(md.contains('Mixed style'), isTrue);

      // Verify buildTextSpan applies combined styling without throwing
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final span = controller.buildTextSpan(
                context: context,
                style: const TextStyle(fontSize: 16),
                withComposing: false,
              );
              expect(span, isNotNull);
              return Text.rich(span);
            },
          ),
        ),
      );
    });

    test('preserveWhitespace keeps multiple internal spaces and enters but removes trailing', () {
      const input = 'Hello     world\n\n\n\nHow are you?    \n\n';
      final output = TextMessageWidget.preserveWhitespace(input);

      // Trailing spaces and enters are removed
      expect(output.endsWith('\n'), isFalse);
      expect(output.endsWith(' '), isFalse);

      // Internal spaces are preserved with non-breaking spaces
      expect(output.contains('Hello \u00A0 \u00A0 world'), isTrue);

      // Internal multiple enters are preserved with non-breaking space empty lines
      expect(output.contains('\n\u00A0\n\u00A0\n\u00A0\nHow are you?'), isTrue);
    });

    test('preserveWhitespace does not modify contents inside code blocks', () {
      const input = 'Normal     text\n```python\ndef foo():\n    return 42\n```\n   \n';
      final output = TextMessageWidget.preserveWhitespace(input);

      // Code block content is untouched
      expect(output.contains('```python\ndef foo():\n    return 42\n```'), isTrue);

      // Normal text before code block has internal spaces preserved
      expect(output.contains('Normal \u00A0 \u00A0 text'), isTrue);

      // Trailing spaces/enters after code block are trimmed
      expect(output.endsWith('```'), isTrue);
    });

    test('preserveWhitespace does not inject non-breaking spaces inside LaTeX formulas', () {
      const input = r'Formula: $x_1   +   x_2 = 5$ and block:' '\n' r'$$\begin{pmatrix} 1   &   2 \\ 3   &   4 \end{pmatrix}$$';
      final output = TextMessageWidget.preserveWhitespace(input);

      expect(output.contains('\u00A0'), isFalse);
      expect(output.contains(r'$x_1   +   x_2 = 5$'), isTrue);
      expect(output.contains(r'$$\begin{pmatrix} 1   &   2 \\ 3   &   4 \end{pmatrix}$$'), isTrue);
    });

    test('parseMarkdown protects LaTeX formulas and inline code from delimiter stripping', () {
      const input = r'Check $f^*(x) + g^*(y) = x_{1} + y_{2}$ and `def __init__(self, *args, **kwargs):` with **bold**';
      final parsed = EntityParser.parseMarkdown(input);

      // LaTeX formula and inline code contents must remain completely intact
      expect(parsed.cleanText.contains(r'$f^*(x) + g^*(y) = x_{1} + y_{2}$'), isTrue);
      expect(parsed.cleanText.contains('def __init__(self, *args, **kwargs):'), isTrue);

      // Only 'code' and 'bold' entities should be created (no bogus italic/underline inside LaTeX or code)
      expect(parsed.entities.map((e) => e.type).toList(), equals(['code', 'bold']));

      final reconstructed = EntityParser.toMarkdown(parsed.cleanText, parsed.entities);
      expect(reconstructed, equals(input));
    });

    test('parseMarkdown does not turn CLI flags or markdown table dashes into underline', () {
      const input = 'Run flutter analyze --no-pub --fatal-infos and __real underline__';
      final parsed = EntityParser.parseMarkdown(input);

      expect(parsed.cleanText, equals('Run flutter analyze --no-pub --fatal-infos and real underline'));
      expect(parsed.entities.length, equals(1));
      expect(parsed.entities.first.type, equals('underline'));
    });

    test('toMarkdown handles mid-line blockquote by inserting line breaks before and after quote', () {
      const text = 'Привет цитата пока';
      const entities = [
        MessageEntity(type: 'blockquote', offset: 7, length: 6, collapsed: false),
      ];

      final md = EntityParser.toMarkdown(text, entities);
      expect(md, equals('Привет \n> цитата\n пока'));
    });

    test('toMarkdown and parseMarkdown handle overlapping (crossing) italic and spoiler modes cleanly', () {
      // "один два три": italic on "один два" [0, 8], spoiler on "два три" [5, 12]
      const text = 'один два три';
      const entities = [
        MessageEntity(type: 'italic', offset: 0, length: 8),
        MessageEntity(type: 'spoiler', offset: 5, length: 7),
      ];

      final md = EntityParser.toMarkdown(text, entities);
      // Italic splits at spoiler boundary and trims trailing space: "*один* ||*два* три||"
      expect(md, equals('*один* ||*два* три||'));

      final reparsed = EntityParser.parseMarkdown(md);
      expect(reparsed.cleanText, equals(text));
      expect(reparsed.entities.any((e) => e.type == 'spoiler' && e.offset == 5 && e.length == 7), isTrue);
      expect(reparsed.entities.where((e) => e.type == 'italic').length, equals(2));
    });

    test('parseMarkdown handles nested bold + italic in all combinations', () {
      final p1 = EntityParser.parseMarkdown('***bold italic***');
      expect(p1.cleanText, equals('bold italic'));
      expect(p1.entities.map((e) => e.type).toSet(), equals({'bold', 'italic'}));

      final p2 = EntityParser.parseMarkdown('**bold *and italic***');
      expect(p2.cleanText, equals('bold and italic'));
      expect(
        p2.entities.any((e) => e.type == 'bold' && e.offset == 0 && e.length == 15),
        isTrue,
      );
      expect(
        p2.entities.any((e) => e.type == 'italic' && e.offset == 5 && e.length == 10),
        isTrue,
      );

      final p3 = EntityParser.parseMarkdown('*italic **and bold***');
      expect(p3.cleanText, equals('italic and bold'));
      expect(
        p3.entities.any((e) => e.type == 'italic' && e.offset == 0 && e.length == 15),
        isTrue,
      );
      expect(
        p3.entities.any((e) => e.type == 'bold' && e.offset == 7 && e.length == 8),
        isTrue,
      );
    });

    test('toMarkdown splits inline formatting across newlines and blockquote boundaries', () {
      const text = 'Первая\nВторая';
      const entities = [
        MessageEntity(type: 'bold', offset: 0, length: 13),
        MessageEntity(type: 'blockquote', offset: 7, length: 6, collapsed: false),
      ];

      final md = EntityParser.toMarkdown(text, entities);
      expect(md, equals('**Первая**\n> **Вторая**'));
    });

    test('RichTextEditingController supports stacking multiple active formats and exits span when toggled off', () {
      final ctrl = RichTextEditingController();
      ctrl.selection = const TextSelection.collapsed(offset: 0);

      // Enable both italic and spoiler at the same time
      ctrl.applyFormat('italic');
      ctrl.applyFormat('spoiler');
      expect(ctrl.isFormatActive('italic'), isTrue);
      expect(ctrl.isFormatActive('spoiler'), isTrue);

      ctrl.value = const TextEditingValue(
        text: 'секрет',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(ctrl.entities.map((e) => e.type).toSet(), equals({'italic', 'spoiler'}));

      // Disable spoiler, keep italic active, and type more
      ctrl.applyFormat('spoiler');
      expect(ctrl.isFormatActive('spoiler'), isFalse);
      expect(ctrl.isFormatActive('italic'), isTrue);

      ctrl.value = const TextEditingValue(
        text: 'секрет курсив',
        selection: TextSelection.collapsed(offset: 13),
      );

      final spoilerEntity = ctrl.entities.firstWhere((e) => e.type == 'spoiler');
      final italicEntity = ctrl.entities.firstWhere((e) => e.type == 'italic');
      expect(spoilerEntity.offset, equals(0));
      expect(spoilerEntity.length, equals(6)); // Only "секрет" is spoiler!
      expect(italicEntity.offset, equals(0));
      expect(italicEntity.length, equals(13)); // Full "секрет курсив" is merged italic!
    });
  });
}
