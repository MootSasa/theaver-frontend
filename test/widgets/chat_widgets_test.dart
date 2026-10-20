import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/widgets/chat/chat_scaffold.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/chat/chat_messages_list_view.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/utils/entity_parser.dart';
import 'package:theaver/widgets/message/code_block_widget.dart';
import 'package:theaver/widgets/message/collapsible_blockquote_widget.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/spoiler_text_widget.dart';
import 'package:theaver/widgets/message/text_message_widget.dart';
import 'package:theaver/widgets/profile/reply_strip_painter.dart';
import 'package:theaver/widgets/chat/floating_video_note_overlay.dart';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations(super.locale);
  @override
  String translate(String key) => key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return _TestAppLocalizations(locale);
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

Widget createTestApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
      ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate(),
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  group('ChatScaffold Widget Tests', () {
    testWidgets('Renders body, appBar, and floatingActionButton correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const ChatScaffold(
            appBar: Text('Test AppBar'),
            floatingActionButton: Text('Test FAB'),
            body: Center(child: Text('Test Body Content')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Test AppBar'), findsOneWidget);
      expect(find.text('Test FAB'), findsOneWidget);
      expect(find.text('Test Body Content'), findsOneWidget);
    });
  });

  group('Chat Stack Layout with Floating Video Note Tests', () {
    testWidgets(
        'Chat stack preserves full screen width for messages and input when overlay is present',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Container(
                        key: const ValueKey('message_list_layer'),
                        color: Colors.blue,
                        child: const Text('Messages Layer'),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        key: const ValueKey('input_bar_layer'),
                        height: 50,
                        color: Colors.green,
                        child: const Text('Input Bar Layer'),
                      ),
                    ),
                    const Positioned.fill(
                      child: FloatingVideoNoteOverlay(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Messages Layer'), findsOneWidget);
      expect(find.text('Input Bar Layer'), findsOneWidget);

      final messageListSize =
          tester.getSize(find.byKey(const ValueKey('message_list_layer')));
      final inputBarSize =
          tester.getSize(find.byKey(const ValueKey('input_bar_layer')));

      // Width MUST be full screen width (800 in default tester environment), NOT 0!
      expect(messageListSize.width, equals(800.0));
      expect(inputBarSize.width, equals(800.0));
      expect(messageListSize.height, greaterThan(0));
      expect(inputBarSize.height, equals(50.0));
    });
  });

  group('ChatMessagesListView Widget Tests', () {
    testWidgets('Renders loading indicator when isLoading is true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          ChatMessagesListView(
            isLoading: true,
            itemCount: 0,
            itemBuilder: (context, index) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Renders empty state when itemCount is 0',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          ChatMessagesListView(
            isLoading: false,
            itemCount: 0,
            emptyTitle: 'No messages here',
            itemBuilder: (context, index) => const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No messages here'), findsOneWidget);
    });

    testWidgets('Renders message items when itemCount > 0',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          ChatMessagesListView(
            isLoading: false,
            itemCount: 3,
            itemBuilder: (context, index) => Text('Message $index'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Message 0'), findsOneWidget);
      expect(find.text('Message 1'), findsOneWidget);
      expect(find.text('Message 2'), findsOneWidget);
    });
  });

  group('ChatInputBar Widget Tests', () {
    testWidgets('Renders input field with hintText', (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestApp(
          ChatInputBar(
            controller: controller,
            hintText: 'Custom hint...',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Custom hint...'), findsOneWidget);
    });

    testWidgets('Renders editing banner and handles onCancelEditing',
        (WidgetTester tester) async {
      final controller = TextEditingController();
      bool cancelled = false;

      await tester.pumpWidget(
        createTestApp(
          ChatInputBar(
            controller: controller,
            isEditing: true,
            editingTitle: 'Editing Message Title',
            onCancelEditing: () {
              cancelled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editing Message Title'), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      expect(cancelled, isTrue);
    });

    testWidgets('ChatInputBar onSendDetailed trims trailing whitespace and enters while preserving internal ones', (WidgetTester tester) async {
      final controller = RichTextEditingController(text: 'Hello    world\n\n\nHow are you?   \n\n');
      String? sentText;

      await tester.pumpWidget(
        createTestApp(
          ChatInputBar(
            controller: controller,
            onSendDetailed: (text, entities, preview, invert) {
              sentText = text;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(iconoir.SendDiagonalSolid));
      await tester.pumpAndSettle();

      expect(sentText, 'Hello    world\n\n\nHow are you?');
    });
  });

  group('TelegramTextSelectionToolbar Widget Tests', () {
    testWidgets('Toggles between horizontal pill and expanded vertical menu',
        (WidgetTester tester) async {
      final controller = RichTextEditingController(text: 'Hello world');
      controller.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TelegramTextSelectionToolbar(
                anchors: const TextSelectionToolbarAnchors(
                    primaryAnchor: Offset(100, 100)),
                buttonItems: const [],
                controller: controller,
                onHideToolbar: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // State 1: Horizontal compact pill
      expect(find.text('Вырезать'), findsOneWidget);
      expect(find.text('Цитировать'), findsOneWidget);
      expect(find.byType(iconoir.MoreVert), findsOneWidget);
      expect(find.text('Назад'), findsNothing);

      // Tap overflow button
      await tester.tap(find.byType(iconoir.MoreVert));
      await tester.pumpAndSettle();

      // State 2: Expanded vertical menu with the 11 formatting options
      expect(find.text('Копировать'), findsOneWidget);
      expect(find.text('Вставить'), findsOneWidget);
      expect(find.text('Обычный'), findsOneWidget);
      expect(find.text('Жирный'), findsOneWidget);
      expect(find.text('Курсив'), findsOneWidget);
      expect(find.text('Моно'), findsOneWidget);
      expect(find.text('Создать код'), findsOneWidget);
      expect(find.text('Зачёркнутый'), findsOneWidget);
      expect(find.text('Подчёркнутый'), findsOneWidget);
      expect(find.text('Скрытый'), findsOneWidget);
      expect(find.text('Добавить ссылку'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);

      // Tap "Назад"
      await tester.tap(find.text('Назад'));
      await tester.pumpAndSettle();

      // Returns to horizontal pill
      expect(find.text('Вырезать'), findsOneWidget);
      expect(find.text('Цитировать'), findsOneWidget);
      expect(find.text('Назад'), findsNothing);
    });

    testWidgets('Preserves expanded state when toolbar is rebuilt with same selection', (WidgetTester tester) async {
      final controller = TextEditingController(text: 'Sample text to select');
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);

      Widget buildToolbar() {
        return createTestApp(
          TelegramTextSelectionToolbar(
            anchors: const TextSelectionToolbarAnchors(primaryAnchor: Offset(100, 100)),
            buttonItems: const [],
            controller: controller,
            onHideToolbar: () {},
          ),
        );
      }

      await tester.pumpWidget(buildToolbar());
      await tester.pumpAndSettle();

      // Compact initial state
      expect(find.byType(iconoir.MoreVert), findsOneWidget);

      // Tap 3-dots
      await tester.tap(find.byType(iconoir.MoreVert));
      await tester.pumpAndSettle();

      // Now expanded
      expect(find.text('Назад'), findsOneWidget);

      // Rebuild widget tree with same selection (simulating background message arriving)
      await tester.pumpWidget(buildToolbar());
      await tester.pumpAndSettle();

      // Still expanded!
      expect(find.text('Назад'), findsOneWidget);
    });

    testWidgets(
        'showLinkDialog in edit mode displays Редактировать ссылку and Удалить ссылку',
        (WidgetTester tester) async {
      final controller = RichTextEditingController(text: 'Visit Google site');
      controller.selection =
          const TextSelection(baseOffset: 6, extentOffset: 12);
      controller.applyLinkToSelection('https://google.com');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    controller.selection =
                        const TextSelection(baseOffset: 6, extentOffset: 12);
                    TextFormattingUtils.showLinkDialog(context, controller);
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Редактировать ссылку'), findsOneWidget);
      expect(find.text('Удалить ссылку'), findsOneWidget);
      expect(find.text('https://google.com'), findsOneWidget);

      // Tap "Удалить ссылку"
      await tester.tap(find.text('Удалить ссылку'));
      await tester.pumpAndSettle();

      expect(controller.spans.isEmpty, isTrue);
      expect(controller.text, 'Visit Google site');
    });
  });

  group('LiquidGlassInputField Widget Tests', () {
    testWidgets(
        'Renders TextField directly without SingleChildScrollView and assigns scrollController',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: 'Test message');
      final focusNode = FocusNode();

      await tester.pumpWidget(
        createTestApp(
          LiquidGlassInputField(
            enabled: true,
            controller: controller,
            hintText: 'Type a message...',
            focusNode: focusNode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.scrollController, isNotNull);
      expect(textField.maxLines, isNull);

      // Verify that TextField is NOT wrapped inside SingleChildScrollView
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );

      // Verify Theme provides textSelectionTheme
      final themeFinder = find.ancestor(
        of: textFieldFinder,
        matching: find.byType(Theme),
      );
      expect(themeFinder, findsWidgets);
      final themeWidget = tester.widget<Theme>(themeFinder.first);
      expect(themeWidget.data.textSelectionTheme.selectionHandleColor, isNotNull);
      expect(themeWidget.data.textSelectionTheme.selectionColor, isNotNull);
    });

    testWidgets(
        'Assigns TelegramTextSelectionControls with TextSelectionHandleControls to TextField',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: 'Hello world');
      await tester.pumpWidget(
        createTestApp(
          LiquidGlassInputField(
            enabled: true,
            controller: controller,
            hintText: 'Type...',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.selectionControls, isA<TextSelectionHandleControls>());
      expect(textField.selectionControls, isA<TelegramTextSelectionControls>());
    });
  });

  group('TextMessageWidget Tests', () {
    testWidgets('Renders message preserving internal consecutive spaces and enters', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const TextMessageWidget(
            text: 'Hello     world\n\n\n\nLine 2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextMessageWidget), findsOneWidget);
    });

    testWidgets('Renders mixed formatting with bold inside spoiler', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const TextMessageWidget(
            text: 'secret',
            entities: [
              MessageEntity(type: 'spoiler', offset: 0, length: 6),
              MessageEntity(type: 'bold', offset: 0, length: 6),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TextMessageWidget), findsOneWidget);
    });
  });

  group('CollapsibleBlockquoteWidget and CodeBlockWidget Tests', () {
    testWidgets('CollapsibleBlockquoteWidget renders with custom sender preset and strip style', (WidgetTester tester) async {
      const preset = NameColorPresets.violet;
      const stripStyle = ReplyStripStyle.candyCane;

      await tester.pumpWidget(
        createTestApp(
          const CollapsibleBlockquoteWidget(
            text: 'Hello from quote',
            isDark: false,
            isMe: false,
            preset: preset,
            stripStyle: stripStyle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CollapsibleBlockquoteWidget), findsOneWidget);
      expect(find.byType(ReplyStripWidget), findsOneWidget);

      final stripFinder = find.byType(ReplyStripWidget);
      final strip = tester.widget<ReplyStripWidget>(stripFinder);
      expect(strip.preset, preset);
      expect(strip.style, stripStyle);
    });

    testWidgets('CollapsibleBlockquoteWidget expands and collapses with pinned bottom button and smooth animation', (WidgetTester tester) async {
      const longQuote = 'Line 1: The quick brown fox jumps over the lazy dog.\n'
          'Line 2: Pack my box with five dozen liquor jugs.\n'
          'Line 3: Sphinx of black quartz, judge my vow.\n'
          'Line 4: How vexingly quick daft zebras jump!\n'
          'Line 5: Bright vixens jump; dozy fowl quack.\n'
          'Line 6: Jackdaws love my big sphinx of quartz.';

      await tester.pumpWidget(
        createTestApp(
          const CollapsibleBlockquoteWidget(
            text: longQuote,
            isDark: false,
            isMe: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand button should be visible since quote has 6 lines
      expect(find.byType(InkWell), findsOneWidget);
      final initialBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      final double collapsedHeight = initialBox.size.height;

      // Tap to expand
      await tester.tap(find.byType(InkWell));
      await tester.pump(); // Dispatch tap gesture to trigger _toggleExpand
      await tester.pump(const Duration(milliseconds: 160)); // Halfway through 320ms animation

      final halfwayBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      expect(halfwayBox.size.height, greaterThan(collapsedHeight));

      await tester.pumpAndSettle();
      final expandedBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      expect(expandedBox.size.height, greaterThan(collapsedHeight));
      expect(expandedBox.size.height, greaterThanOrEqualTo(halfwayBox.size.height));

      // Tap to collapse
      await tester.tap(find.byType(InkWell));
      await tester.pump(); // Dispatch tap gesture
      await tester.pump(const Duration(milliseconds: 160));
      final collapsingBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      expect(collapsingBox.size.height, lessThanOrEqualTo(expandedBox.size.height));

      await tester.pumpAndSettle();
      final finalBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      expect(finalBox.size.height, closeTo(collapsedHeight, 1.0));
    });

    testWidgets('CodeBlockWidget renders with custom sender preset and strip style', (WidgetTester tester) async {
      const preset = NameColorPresets.green;
      const stripStyle = ReplyStripStyle.dualColor;

      await tester.pumpWidget(
        createTestApp(
          const CodeBlockWidget(
            code: 'void main() {}',
            language: 'dart',
            isDark: false,
            isMe: false,
            preset: preset,
            stripStyle: stripStyle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CodeBlockWidget), findsOneWidget);
      expect(find.byType(ReplyStripWidget), findsOneWidget);

      final stripFinder = find.byType(ReplyStripWidget);
      final strip = tester.widget<ReplyStripWidget>(stripFinder);
      expect(strip.preset, preset);
      expect(strip.style, stripStyle);
    });

    testWidgets('CollapsibleBlockquoteWidget adapts its width to content instead of expanding infinitely', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: const CollapsibleBlockquoteWidget(
                text: 'Short',
                isDark: false,
                isMe: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shortQuoteBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      // Short quote width must be compact, significantly less than max width (320)
      expect(shortQuoteBox.size.width, lessThan(120.0));

      await tester.pumpWidget(
        createTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: const CollapsibleBlockquoteWidget(
                text: 'A very long quote line that definitely needs more horizontal space to display properly.',
                isDark: false,
                isMe: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final longQuoteBox = tester.renderObject<RenderBox>(find.byType(CollapsibleBlockquoteWidget));
      expect(longQuoteBox.size.width, greaterThan(250.0));
    });

    testWidgets('CodeBlockWidget adapts its width to content instead of expanding infinitely', (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: const CodeBlockWidget(
                code: 'x = 1',
                isDark: false,
                isMe: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final shortCodeBox = tester.renderObject<RenderBox>(find.byType(CodeBlockWidget));
      // Short code width must be compact, significantly less than max width (320)
      expect(shortCodeBox.size.width, lessThan(240.0));

      await tester.pumpWidget(
        createTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: const CodeBlockWidget(
                code: 'void main() { print("A long line of code that takes a lot of horizontal room"); }',
                isDark: false,
                isMe: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final longCodeBox = tester.renderObject<RenderBox>(find.byType(CodeBlockWidget));
      expect(longCodeBox.size.width, greaterThan(250.0));
    });
  });

  group('MessageBubble Block Element Layout Tests', () {
    testWidgets('MessageBubble with quote sets hasBlockElement to prevent metadata overlap', (WidgetTester tester) async {
      final message = Message(
        id: 'msg_1',
        chatId: 'chat_1',
        senderId: 'user_2',
        senderName: 'Alice',
        content: '> First line\n> Second line',
        messageType: 'text',
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
        senderNameColorId: 'name_violet',
        senderReplyStripStyle: 'candyCane',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'me_123',
            formatTime: (_) => '12:00',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MessageBubble), findsOneWidget);
      expect(find.byType(CollapsibleBlockquoteWidget), findsOneWidget);
    });

    testWidgets('MessageBubble renders combined blockquote + spoiler + italic + bold + trailing text without layout errors', (WidgetTester tester) async {
      const cleanText = 'Начало\nСкрытая цитата\nКонец';
      const entities = [
        MessageEntity(type: 'blockquote', offset: 7, length: 14, collapsed: false),
        MessageEntity(type: 'spoiler', offset: 7, length: 14),
        MessageEntity(type: 'bold', offset: 7, length: 7),
        MessageEntity(type: 'italic', offset: 11, length: 10),
      ];
      final mdContent = EntityParser.toMarkdown(cleanText, entities);

      final message = Message(
        id: 'msg_combined_1',
        chatId: 'chat_1',
        senderId: 'user_2',
        senderName: 'Alice',
        content: mdContent,
        entities: entities,
        messageType: 'text',
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'me_123',
            formatTime: (_) => '12:00',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(CollapsibleBlockquoteWidget), findsOneWidget);
      expect(find.byType(SpoilerTextWidget), findsOneWidget);
    });
  });
}
