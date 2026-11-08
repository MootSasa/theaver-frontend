import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/sticker_service.dart';
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

    testWidgets(
        'Custom emoji in RichTextEditingController renders WidgetSpan with aligned UTF-16 length and tracks edits',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              final controller = RichTextEditingController();
              const item1 = StickerItem(
                id: 101,
                packId: 1,
                fileUrl: '/uploads/stickers/custom_101.webp',
                emojiList: ['🔥'],
                format: 'webp',
              );
              const item2 = StickerItem(
                id: 102,
                packId: 1,
                fileUrl: '/uploads/stickers/custom_102.webp',
                emojiList: ['🔥'],
                format: 'webp',
              );

              controller.insertCustomEmoji(item1);
              controller.insertCustomEmoji(item2);

              // Both custom emojis have fallback '🔥' (UTF-16 length 2 each -> total 4)
              expect(controller.text, '🔥🔥');
              expect(controller.entities.length, 2);
              expect(controller.entities[0].type, 'custom_emoji');
              expect(controller.entities[0].customEmojiId, '101');
              expect(controller.entities[0].offset, 0);
              expect(controller.entities[0].length, 2);
              expect(controller.entities[1].customEmojiId, '102');
              expect(controller.entities[1].offset, 2);
              expect(controller.entities[1].length, 2);

              final span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              // Total plain-text UTF-16 length of InlineSpan tree must match controller.text.length
              expect(span.toPlainText().length, controller.text.length);
              expect(
                span.children!.whereType<WidgetSpan>().length,
                2,
              );

              // Prepend 'Hi ' at offset 0 -> both custom_emoji spans shift by +3
              controller.value = const TextEditingValue(
                text: 'Hi 🔥🔥',
                selection: TextSelection.collapsed(offset: 3),
              );
              expect(controller.entities.length, 2);
              expect(controller.entities[0].offset, 3);
              expect(controller.entities[0].customEmojiId, '101');
              expect(controller.entities[1].offset, 5);
              expect(controller.entities[1].customEmojiId, '102');

              // Delete the first custom emoji at [3, 5] -> only item2 (102) remains at [3, 5]
              controller.value = const TextEditingValue(
                text: 'Hi 🔥',
                selection: TextSelection.collapsed(offset: 3),
              );
              expect(controller.entities.length, 1);
              expect(controller.entities[0].customEmojiId, '102');
              expect(controller.entities[0].offset, 3);
              expect(controller.entities[0].length, 2);

              return const SizedBox();
            }),
          ),
        ),
      );
    });
  });
}
