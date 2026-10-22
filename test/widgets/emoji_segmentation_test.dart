import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/utils/emoji_utils.dart';
import 'package:theaver/widgets/chat/rich_text_editing_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EmojiUtils.isFontLoaded.value = true;
  });

  group('Emoji Segmentation Tests in RichTextEditingController', () {
    testWidgets('Compound ZWJ emoji (female zombie 🧟‍♀️) remains a single TextSpan',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              final controller = RichTextEditingController(text: '🧟‍♀️');
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              // Must have exactly 1 child span containing the full cluster
              expect(span.children, isNotNull);
              expect(span.children!.length, 1);
              final child = span.children!.first as TextSpan;
              expect(child.text, '🧟‍♀️');
              expect(child.style?.fontFamily, EmojiUtils.effectiveFontFamily);

              return const SizedBox();
            }),
          ),
        ),
      );
    });

    testWidgets('Multi-person ZWJ emoji (👨‍👩‍👧‍👦) remains a single TextSpan',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              final controller = RichTextEditingController(text: '👨‍👩‍👧‍👦');
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              expect(span.children!.length, 1);
              final child = span.children!.first as TextSpan;
              expect(child.text, '👨‍👩‍👧‍👦');
              expect(child.style?.fontFamily, EmojiUtils.effectiveFontFamily);

              return const SizedBox();
            }),
          ),
        ),
      );
    });

    testWidgets('Fitzpatrick skin tone emoji (👍🏽) remains a single TextSpan',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              final controller = RichTextEditingController(text: '👍🏽');
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              expect(span.children!.length, 1);
              final child = span.children!.first as TextSpan;
              expect(child.text, '👍🏽');

              return const SizedBox();
            }),
          ),
        ),
      );
    });

    testWidgets('Adjacent distinct emojis (🧟 and ♀️) are NOT merged into female zombie',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              // Typed consecutively without ZWJ
              final controller = RichTextEditingController(text: '🧟♀️');
              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );

              expect(span.children!.length, 2);
              final first = span.children![0] as TextSpan;
              final second = span.children![1] as TextSpan;
              expect(first.text, '🧟');
              expect(second.text, '♀️');

              return const SizedBox();
            }),
          ),
        ),
      );
    });

    testWidgets('EmojiUtils.buildEmojiTextSpan handles compound emojis and mixed text',
        (tester) async {
      const input = 'Hello 🧟‍♀️ and 👨‍👩‍👧‍👦!';
      final span = EmojiUtils.buildEmojiTextSpan(
        input,
        style: const TextStyle(fontSize: 16),
      );

      final children = span.children!;
      expect(children.length, 5);
      expect((children[0] as TextSpan).text, 'Hello ');
      expect((children[1] as TextSpan).text, '🧟‍♀️');
      expect((children[2] as TextSpan).text, ' and ');
      expect((children[3] as TextSpan).text, '👨‍👩‍👧‍👦');
      expect((children[4] as TextSpan).text, '!');
    });
  });
}
