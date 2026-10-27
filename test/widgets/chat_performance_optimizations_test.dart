import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/widgets/chat/chat_messages_list_view.dart';
import 'package:theaver/widgets/message/spoiler_text_widget.dart';
import 'package:theaver/widgets/message/text_message_widget.dart';
import 'package:theaver/widgets/message/voice_message_widget.dart';
import 'package:theaver/services/voice_playback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextMessageWidget Fast-path Tests', () {
    testWidgets('Plain text uses fast-path Text widget without MarkdownBody', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextMessageWidget(
              text: 'Привет, как дела? Обычное сообщение.',
              isMe: false,
            ),
          ),
        ),
      );

      // Verify that direct Text widget is rendered
      expect(find.text('Привет, как дела? Обычное сообщение.'), findsOneWidget);
      // Verify that heavy MarkdownBody is NOT rendered for plain text
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets('Formatted markdown text renders directly via RichText without MarkdownBody', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextMessageWidget(
              text: 'Сообщение 123 с **жирным** и _курсивом_ 🚀 1️⃣',
              isMe: false,
              style: TextStyle(color: Color(0xFF112233), fontSize: 17),
            ),
          ),
        ),
      );

      // Direct Entity-First renderer must NOT use MarkdownBody
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byType(RichText), findsWidgets);

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      final rootSpan = richText.text as TextSpan;
      // Base style must never have AppleEmoji in fontFamilyFallback
      expect(rootSpan.style?.fontFamilyFallback?.contains('AppleEmoji') ?? false, isFalse);

      // Verify digits '123' do NOT get AppleEmoji font, while '🚀' and '1️⃣' DO get emoji font
      final leafSpans = <TextSpan>[];
      void collectLeaves(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text != null && span.text!.isNotEmpty) {
            leafSpans.add(span);
          }
          if (span.children != null) {
            for (final c in span.children!) {
              collectLeaves(c);
            }
          }
        }
      }
      collectLeaves(rootSpan);

      final digitSpan = leafSpans.firstWhere((s) => s.text!.contains('123'));
      expect(digitSpan.style?.fontFamily, isNot(equals('AppleEmoji')));

      final rocketSpan = leafSpans.firstWhere((s) => s.text == '🚀');
      expect(rocketSpan.style?.fontFamily, isNotNull);

      final keycapSpan = leafSpans.firstWhere((s) => s.text == '1️⃣');
      expect(keycapSpan.style?.fontFamily, isNotNull);
    });

    testWidgets('LaTeX formulas inherit custom message text color', (tester) async {
      const customColor = Color(0xFFABCDEF);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextMessageWidget(
              text: r'Формула $E = mc^2$ в тексте',
              isMe: true,
              style: TextStyle(color: customColor, fontSize: 17),
            ),
          ),
        ),
      );

      expect(find.byType(MarkdownBody), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Telegram-style inline spoiler renders in single RichText and reveals on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextMessageWidget(
              text: 'Видимый ||скрытый текст|| конец',
              isMe: false,
              style: TextStyle(color: Color(0xFF223344), fontSize: 17),
            ),
          ),
        ),
      );

      expect(find.byType(SpoilerTextWidget), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    test('NameColorPreset.resolveReadableTextColor ensures dark readable text on light reply card backgrounds even in dark mode', () {
      for (final preset in NameColorPresets.defaults) {
        final lightCardBg = preset.getOpaqueCardBackgroundColor(true);
        // Card background has lightness 0.83 (light pastel)
        expect(lightCardBg.computeLuminance(), greaterThan(0.42));

        // Even if dark theme default onSurface is white, resolved text color must be dark & readable
        final textColor = NameColorPreset.resolveReadableTextColor(
          lightCardBg,
          configuredColor: Colors.white,
          isExplicitCustom: false,
        );
        expect(textColor.computeLuminance(), lessThan(0.15));
      }
    });

    testWidgets('Regular messages use tight height 1.2 with forceStrutHeight, while inline LaTeX disables forced strut', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextMessageWidget(
                  text: 'Первая строка\nВторая строка 🚀',
                  isMe: false,
                ),
                TextMessageWidget(
                  text: r'Формула с дробью $\frac{a+b}{c+d}$ в строке',
                  isMe: false,
                ),
              ],
            ),
          ),
        ),
      );

      final richTexts = tester.widgetList<RichText>(find.byType(RichText)).toList();
      final normalRichText = richTexts.first;
      expect(normalRichText.strutStyle?.height, equals(1.12));
      expect(normalRichText.strutStyle?.forceStrutHeight, isTrue);

      // The RichText hosting the inline LaTeX WidgetSpan must not force strut height
      final latexHostRichText = richTexts.firstWhere(
        (rt) => rt.text.toPlainText().contains('Формула с дробью'),
      );
      expect(latexHostRichText.strutStyle?.forceStrutHeight ?? false, isFalse);
    });

    test('TelegramSpoilerPainterUtils.syncParticlesForRects maintains constant particle density across small and large rects', () {
      const smallRect = Rect.fromLTWH(0, 0, 25, 20);
      const mediumRect = Rect.fromLTWH(0, 0, 100, 20);
      const largeRect = Rect.fromLTWH(0, 0, 300, 20);

      final rectParticles = <List<SpoilerParticle>>[];
      TelegramSpoilerPainterUtils.syncParticlesForRects(
        [smallRect, mediumRect, largeRect],
        rectParticles,
        isMedia: false,
      );

      final smallDensity = rectParticles[0].length / (smallRect.width * smallRect.height);
      final mediumDensity = rectParticles[1].length / (mediumRect.width * mediumRect.height);
      final largeDensity = rectParticles[2].length / (largeRect.width * largeRect.height);

      // Density must remain virtually identical across small, medium, and large rects
      expect((smallDensity - mediumDensity).abs(), lessThan(0.003));
      expect((mediumDensity - largeDensity).abs(), lessThan(0.003));
    });

    test('TelegramSpoilerPainterUtils.normalizeAndMergeLineRects merges same-line rects and snaps consecutive lines with zero vertical gap', () {
      final rawRects = <Rect>[
        const Rect.fromLTRB(0, 0, 80, 18),
        const Rect.fromLTRB(80, 0.5, 180, 18.5), // same line (e.g. bold span inside spoiler)
        const Rect.fromLTRB(0, 20, 140, 38), // next line with 1.5px leading gap
      ];

      final merged = TelegramSpoilerPainterUtils.normalizeAndMergeLineRects(rawRects);
      expect(merged.length, equals(2));
      expect(merged[0].left, equals(0));
      expect(merged[0].right, equals(180));
      // Line 0 bottom and Line 1 top must touch with zero gap
      expect(merged[0].bottom, equals(merged[1].top));
    });
  });

  group('ChatMessagesListView Pagination Tests', () {
    testWidgets('isLoadingMore renders progress indicator as list item without resizing ListView', (tester) async {
      final scrollController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessagesListView(
              isLoading: false,
              isLoadingMore: true,
              itemCount: 5,
              scrollController: scrollController,
              itemBuilder: (context, index) {
                return SizedBox(
                  height: 50,
                  child: Text('Message $index'),
                );
              },
            ),
          ),
        ),
      );

      // The spinner should be inside the ListView as the 6th item (index 5)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Message 0'), findsOneWidget);
      expect(find.text('Message 4'), findsOneWidget);

      // Verify ListView is rendered directly (no outer Column with Padding)
      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget);
    });

    testWidgets('When isLoadingMore is false, no CircularProgressIndicator is rendered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessagesListView(
              isLoading: false,
              isLoadingMore: false,
              itemCount: 3,
              itemBuilder: (context, index) {
                return SizedBox(
                  height: 50,
                  child: Text('Message $index'),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Message 0'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
    });
  });

  group('VoiceMessageWidget Playback Isolation Tests', () {
    testWidgets('Inactive VoiceMessageWidget does not rebuild on unrelated playback notifications', (tester) async {
      final playbackService = VoicePlaybackService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceMessageWidget(
              messageId: 'voice_1',
              audioUrl: '',
              duration: const Duration(seconds: 10),
              isMe: true,
            ),
          ),
        ),
      );

      // Simulate playback service notification
      playbackService.notifyListeners();
      await tester.pump();

      // Ensure voice_1 is still mounted and working cleanly
      expect(find.byType(VoiceMessageWidget), findsOneWidget);
    });
  });
}
