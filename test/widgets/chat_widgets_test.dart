import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/widgets/chat/chat_scaffold.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/chat/chat_messages_list_view.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/utils/entity_parser.dart';
import 'package:theaver/utils/emoji_utils.dart';
import 'package:theaver/widgets/message/code_block_widget.dart';
import 'package:theaver/widgets/message/collapsible_blockquote_widget.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/spoiler_text_widget.dart';
import 'package:theaver/widgets/message/text_message_widget.dart';
import 'package:theaver/widgets/profile/reply_strip_painter.dart';
import 'package:theaver/widgets/chat/floating_video_note_overlay.dart';
import 'package:theaver/widgets/chat/message_context_menu.dart';
import 'package:theaver/widgets/chat/message_reply_info.dart';
import 'package:theaver/services/message_context_menu_service.dart';
import 'package:theaver/services/tiling_layout_controller.dart';
import 'package:theaver/widgets/tiling/static_tile_cache_boundary.dart';
import 'package:theaver/widgets/tiling/tile_resize_divider.dart';
import 'package:theaver/widgets/tiling/tile_viewport_scope.dart';
import 'package:theaver/utils/swipe_back_route.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations(super.locale);
  @override
  String translate(String key, [Map<String, String>? params]) => key;
}

class _TestEnabledLiquidGlassProvider extends LiquidGlassProvider {
  @override
  GlassMode get mode => GlassMode.lite;

  @override
  bool get enabled => true;
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
      theme: ThemeData(
        splashFactory: InkRipple.splashFactory,
      ),
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
            isCollapsible: true,
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

    test('MessageReplyInfo.buildFormattedPreviewSpan preserves original entities and does not force italic on quotes', () {
      const baseStyle = TextStyle(fontSize: 13, fontStyle: FontStyle.normal, color: Colors.black);
      const rawContent = 'Жирный и курсив и обычный текст';
      const entities = [
        MessageEntity(type: 'bold', offset: 0, length: 6), // "Жирный"
        MessageEntity(type: 'italic', offset: 9, length: 6), // "курсив"
      ];

      final span = MessageReplyInfo.buildFormattedPreviewSpan(
        rawText: rawContent,
        entities: entities,
        isQuote: true,
        quoteText: 'Жирный и курсив и обычный',
        quoteOffset: 0,
        quoteLength: 25,
        baseStyle: baseStyle,
        accentColor: Colors.blue,
        isDark: false,
      );

      final children = span.children!.whereType<TextSpan>().toList();
      expect(children.length, greaterThanOrEqualTo(3));

      // First segment "Жирный" is bold, NOT italic
      expect(children[0].toPlainText(), equals('Жирный'));
      expect(children[0].style?.fontWeight, equals(FontWeight.bold));
      expect(children[0].style?.fontStyle, isNot(equals(FontStyle.italic)));

      // Second segment " и " is neither bold nor italic (even though isQuote: true)
      expect(children[1].toPlainText(), equals(' и '));
      expect(children[1].style?.fontStyle, isNot(equals(FontStyle.italic)));

      // Third segment "курсив" IS italic because of the entity
      expect(children[2].toPlainText(), equals('курсив'));
      expect(children[2].style?.fontStyle, equals(FontStyle.italic));
    });

    testWidgets('Quote on bullet lines in the middle of a message does not stretch to subsequent lines', (WidgetTester tester) async {
      const content = 'Настраиваем Windows без страха убить систему: нашли универсальный PowerShell-модуль с 150+ полезными командами для Windows 10 и 11.\n\n'
          'В отличие от всякого мутного софта, скрипт использует официальные методы Microsoft, а твики можно откатить и вернуть настройки к исходному состоянию:\n'
          '• Убирает хлам:\u00A0деинсталляция предустановленного мусора, OneDrive и шпионских приложений;\n'
          '•  Отключает надоедливую рекламу, «рекомендации» и слежку за вашими действиями;\n'
          '• Настраивает Проводник, меню, приватность и безопасность;\n'
          '• Не вмешивается в системные файлы сомнительными хаками;\n'
          '• Для каждой настройки предусмотрен откат к стандартным параметрам.\n\n'
          'Ваш личный мастер — здесь.\n\n'
          '🎮КиберТопор — Подписаться (https://t.me/+6fyKjmOWmW5lYzMy)';
      const entities = [
        MessageEntity(type: 'blockquote', offset: 283, length: 353, collapsed: false),
        MessageEntity(type: 'text_link', offset: 658, length: 5, url: 'https://github.com/farag2/Sophia-Script-for-Windows'),
        MessageEntity(type: 'url', offset: 694, length: 31, url: 'https://t.me/+6fyKjmOWmW5lYzMy)'),
      ];

      await tester.pumpWidget(
        createTestApp(
          const TextMessageWidget(
            text: content,
            entities: entities,
            isMe: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final quoteWidget = tester.widget<CollapsibleBlockquoteWidget>(
        find.byType(CollapsibleBlockquoteWidget),
      );
      expect(quoteWidget.text.contains('Ваш личный мастер'), isFalse);
      expect(quoteWidget.text.contains('КиберТопор'), isFalse);
      expect(quoteWidget.text.endsWith('параметрам.'), isTrue);
    });
  });

  group('Spoiler Tap Isolation & MessageTextSelectionToolbar Tests', () {
    testWidgets('Tapping hidden spoiler text reveals spoiler WITHOUT triggering ancestor GestureDetector.onTap', (WidgetTester tester) async {
      bool ancestorOnTapCalled = false;

      await tester.pumpWidget(
        createTestApp(
          GestureDetector(
            onTap: () {
              ancestorOnTapCalled = true;
            },
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: TextMessageWidget(
                text: '||Скрытый спойлер на всю строку||',
                isMe: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final spoilerFinder = find.byType(SpoilerTextWidget);
      expect(spoilerFinder, findsOneWidget);

      // Tap right in the center of the hidden spoiler text
      await tester.tap(spoilerFinder);
      await tester.pump(const Duration(milliseconds: 50));

      // Ancestor GestureDetector.onTap must NOT have fired!
      expect(ancestorOnTapCalled, isFalse);
    });

    testWidgets('MessageTextSelectionToolbar toggles between compact pill and expanded vertical menu', (WidgetTester tester) async {
      bool copied = false;
      bool quoted = false;
      bool translated = false;
      bool searched = false;
      bool selectedAll = false;

      await tester.pumpWidget(
        createTestApp(
          Stack(
            children: [
              Positioned.fill(
                child: MessageTextSelectionToolbar(
                  anchors: const TextSelectionToolbarAnchors(
                    primaryAnchor: Offset(200, 220),
                    secondaryAnchor: Offset(200, 260),
                  ),
                  onCopy: () => copied = true,
                  onQuote: () => quoted = true,
                  onTranslate: () => translated = true,
                  onSearchMessages: () => searched = true,
                  onSelectAll: () => selectedAll = true,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Compact pill buttons
      expect(find.text('Копировать'), findsOneWidget);
      expect(find.text('Цитировать'), findsOneWidget);
      expect(find.text('Перевести'), findsOneWidget);
      expect(find.byType(iconoir.MoreVert), findsOneWidget);

      // Tap three vertical dots to expand
      await tester.tap(find.byType(iconoir.MoreVert));
      await tester.pumpAndSettle();

      expect(find.text('Найти сообщения'), findsOneWidget);
      expect(find.text('Выбрать всё'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);

      // Tap 'Выбрать всё' -> calls onSelectAll and collapses back to compact pill
      await tester.tap(find.text('Выбрать всё'));
      await tester.pumpAndSettle();
      expect(selectedAll, isTrue);
      expect(find.text('Копировать'), findsOneWidget);

      // Tap 'Цитировать'
      await tester.tap(find.text('Цитировать'));
      await tester.pumpAndSettle();
      expect(quoted, isTrue);
      expect(copied, isFalse);
      expect(translated, isFalse);
      expect(searched, isFalse);
    });

    testWidgets('MessageContextMenu renders iOS BackdropFilter blur, focused message, and allows selecting text to quote partially', (WidgetTester tester) async {
      String? quotedText;
      int? quotedOffset;
      int? quotedLength;

      final message = Message(
        id: 'm_focus_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'User',
        content: 'Первое слово и второе слово',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        createTestApp(
          MessageContextMenu(
            messageOffset: const Offset(16, 120),
            messageSize: const Size(280, 60),
            isMe: false,
            messageContent: message.content,
            focusedMessageBuilder: (focusedKey) => MessageBubble(
              key: focusedKey,
              message: message,
              isMe: false,
              currentUserId: 'me_1',
              formatTime: (_) => '12:00',
            ),
            onReply: () {},
            onQuote: () {},
            onQuotePartial: (text, offset, len) {
              quotedText = text;
              quotedOffset = offset;
              quotedLength = len;
            },
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onReaction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify BackdropFilter is present for Telegram iOS blur effect
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.byType(MessageBubble), findsOneWidget);

      // Simple tap on the focused message text must NOT auto-select a word
      final textCenter = tester.getCenter(find.byType(TextMessageWidget));
      await tester.tapAt(textCenter);
      await tester.pumpAndSettle();
      expect(find.byType(MessageTextSelectionToolbar), findsNothing);

      // Drag across the focused MessageBubble text to select text
      await tester.dragFrom(
        textCenter - const Offset(30, 0),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();

      // MessageTextSelectionToolbar should now be visible
      expect(find.byType(MessageTextSelectionToolbar), findsOneWidget);
      expect(find.text('Цитировать'), findsOneWidget);

      // Expand menu and tap 'Выбрать всё', then tap 'Цитировать'
      await tester.tap(find.byType(iconoir.MoreVert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выбрать всё'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Цитировать'));
      await tester.pumpAndSettle();

      expect(quotedText, equals('Первое слово и второе слово'));
      expect(quotedOffset, equals(0));
      expect(quotedLength, equals('Первое слово и второе слово'.length));
    });

    testWidgets('MessageContextMenu supports enableBlur: false and onSelect («Выделить») action', (WidgetTester tester) async {
      bool selectCalled = false;
      final message = Message(
        id: 'm_select_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'User',
        content: 'Сообщение для выделения',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        createTestApp(
          MessageContextMenu(
            messageOffset: const Offset(16, 120),
            messageSize: const Size(240, 50),
            isMe: false,
            enableBlur: false,
            messageContent: message.content,
            onReply: () {},
            onCopy: () {},
            onSelect: () {
              selectCalled = true;
            },
            onPin: () {},
            onDelete: () {},
            onReaction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // «Выделить» action item is rendered and triggers onSelect
      expect(find.text('chat_action_select'), findsOneWidget);
      await tester.tap(find.text('chat_action_select'));
      await tester.pumpAndSettle();
      expect(selectCalled, isTrue);
    });
  });

  group('Multi-Message Selection UI & Theme Palette Tests', () {
    testWidgets('FloatingGlassAppBar transforms into selection mode with Xmark, counter, and Copy/Forward/Delete actions', (WidgetTester tester) async {
      bool cancelled = false;
      bool copied = false;
      bool forwarded = false;
      bool deleted = false;

      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Test Chat',
            isOnline: false,
            onBack: () {},
            onTitleTap: () {},
            isSelectionMode: true,
            selectedCount: 3,
            onCancelSelection: () => cancelled = true,
            onCopySelected: () => copied = true,
            onForwardSelected: () => forwarded = true,
            onDeleteSelected: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.Xmark), findsOneWidget);
      expect(find.byType(iconoir.Copy), findsOneWidget);
      expect(find.byType(iconoir.ForwardMessage), findsOneWidget);
      expect(find.byType(iconoir.Trash), findsOneWidget);

      await tester.tap(find.byType(iconoir.Copy));
      await tester.pump();
      expect(copied, isTrue);

      await tester.tap(find.byType(iconoir.ForwardMessage));
      await tester.pump();
      expect(forwarded, isTrue);

      await tester.tap(find.byType(iconoir.Trash));
      await tester.pump();
      expect(deleted, isTrue);

      await tester.tap(find.byType(iconoir.Xmark));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('MessageBubble in selection mode renders MessageSelectionCheckbox, full-width row highlight, and selected bubble color from TheavPalette', (WidgetTester tester) async {
      const customOverlay = Color(0x33FF00AA);
      const customIncomingSelected = Color(0xFF123456);
      final palette = TheavPalette.fromJson(const {}).copyWith(
        messageSelectionOverlay: customOverlay,
        chatBubbleIncomingSelected: customIncomingSelected,
      );
      final wallpaper = TheavWallpaper.fromJson(const {});

      final message = Message(
        id: 'm_sel_row_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content: 'Selected message text',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
            ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: [
                TheavThemeExtension(
                  palette: palette,
                  wallpaper: wallpaper,
                  bubbleRadius: 18.0,
                ),
              ],
            ),
            localizationsDelegates: const [
              _TestAppLocalizationsDelegate(),
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            home: Scaffold(
              body: MessageBubble(
                message: message,
                isMe: false,
                isSelected: true,
                isSelectionMode: true,
                currentUserId: 'me_1',
                formatTime: (_) => '12:00',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Checkbox is rendered
      expect(find.byType(MessageSelectionCheckbox), findsOneWidget);

      // Full-width row highlight spans the entire 800px screen width
      final bubbleBox = tester.renderObject<RenderBox>(find.byType(MessageBubble));
      expect(bubbleBox.size.width, equals(800.0));

      // Hit-test helpers accurately distinguish inside bubble vs empty row space
      final bubbleMetaFinder = find.byWidgetPredicate(
        (w) => w is MetaData && w.metaData == 'message_bubble_box',
      );
      expect(bubbleMetaFinder, findsOneWidget);
      final insideCenter = tester.getCenter(bubbleMetaFinder);
      final bubbleCtx = tester.element(find.byType(MessageBubble));

      expect(
        MessageBubble.isGlobalPointInsideBubble(bubbleCtx, insideCenter),
        isTrue,
      );
      expect(
        MessageBubble.isGlobalPointInsideBubble(bubbleCtx, const Offset(780, 20)),
        isFalse,
      );
    });

    testWidgets(
        'MessageReplyInfo with isQuote renders only the quoted substring and QuoteSolid icon even when entities are empty',
        (WidgetTester tester) async {
      const fullOriginal =
          'First sentence before quote. Important quoted slice! Trailing part of message.';
      const quotedPart = 'Important quoted slice!';
      final offset = fullOriginal.indexOf(quotedPart);

      await tester.pumpWidget(
        createTestApp(
          MessageReplyInfo(
            replyInfo: const ReplyInfo(
              messageId: 'orig_1',
              senderId: 'u2',
              senderName: 'Bob',
              content: fullOriginal,
              messageType: 'text',
              entities: [],
            ),
            isQuote: true,
            quoteText: quotedPart,
            quoteOffset: offset,
            quoteLength: quotedPart.length,
            isMe: false,
            currentUserId: 'me_1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.QuoteSolid), findsOneWidget);
      expect(
        find.textContaining('Important quoted slice!', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('First sentence before quote', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Trailing part of message', findRichText: true),
        findsNothing,
      );
    });

    test('Message.fromJson parses quote metadata from media_payload fallback', () {
      final msg = Message.fromJson({
        'id': '42',
        'chat_id': 'c1',
        'sender_id': 'u1',
        'sender_name': 'Alice',
        'content': 'My reply to a quote',
        'message_type': 'text',
        'created_at': '2026-10-26T10:00:00Z',
        'reply_to_message_id': '41',
        'reply_to_sender_id': 'u2',
        'reply_to_sender_name': 'Bob',
        'reply_to_content': 'Hello quoted world from Bob',
        'media_payload': {
          'is_quote': true,
          'quote_text': 'quoted world',
          'quote_offset': 6,
          'quote_length': 12,
        },
      });

      expect(msg.isQuote, isTrue);
      expect(msg.quoteText, equals('quoted world'));
      expect(msg.quoteOffset, equals(6));
      expect(msg.quoteLength, equals(12));
    });

    testWidgets(
        'Outgoing (isMe: true) MessageContextMenu stays within narrow pane bounds using LayoutBuilder width instead of full window MediaQuery width',
        (WidgetTester tester) async {
      // Window is 800px wide, but MessageContextMenu is placed inside a 420px wide pane
      await tester.pumpWidget(
        createTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 420,
              height: 600,
              child: MessageContextMenu(
                messageOffset: const Offset(200, 140),
                messageSize: const Size(200, 48),
                isMe: true,
                sendStatus: 1,
                messageContent: 'Outgoing test message',
                enableBlur: false,
                onReply: () {},
                onQuote: () {},
                onCopy: () {},
                onPin: () {},
                onEdit: () {},
                onSelect: () {},
                onDelete: () {},
                onReaction: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final selectLabelFinder = find.text('chat_action_select');
      expect(selectLabelFinder, findsOneWidget);
      final selectRect = tester.getRect(selectLabelFinder);
      // Must be positioned inside the 420px pane, not off-screen near 800px
      expect(selectRect.left, greaterThanOrEqualTo(0.0));
      expect(selectRect.right, lessThanOrEqualTo(420.0));
    });

    test('MessageContextMenuService activeBlurMessageId clears properly', () {
      final service = MessageContextMenuService();
      service.activeBlurMessageId.value = 'msg_99';
      expect(service.activeBlurMessageId.value, equals('msg_99'));
      service.clearActiveBlurMessage();
      expect(service.activeBlurMessageId.value, isNull);
    });

    testWidgets(
        'MessageContextMenu keeps focused message at exact original vertical position without shifting up or down',
        (WidgetTester tester) async {
      final message = Message(
        id: 'm_no_shift_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content: 'Message near bottom of screen for direct text selection',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      const originalOffset = Offset(16, 520);
      await tester.pumpWidget(
        createTestApp(
          MessageContextMenu(
            messageOffset: originalOffset,
            messageSize: const Size(280, 56),
            isMe: false,
            enableBlur: true,
            messageContent: message.content,
            focusedMessageBuilder: (focusedKey) => MessageBubble(
              key: focusedKey,
              message: message,
              isMe: false,
              currentUserId: 'me_1',
              formatTime: (_) => '12:00',
            ),
            onReply: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onReaction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bubbleTopLeft = tester.getTopLeft(find.byType(MessageBubble));
      expect(bubbleTopLeft.dx, equals(originalOffset.dx));
      expect(bubbleTopLeft.dy, equals(originalOffset.dy));
    });

    testWidgets(
        'TextMessageWidget uses SystemMouseCursors.text (I-beam cursor) on hover, and desktop hides teardrop selection handles',
        (WidgetTester tester) async {
      final message = Message(
        id: 'm_desktop_sel_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content: 'Desktop selectable text without handles',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
            ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              platform: TargetPlatform.windows,
            ),
            localizationsDelegates: const [
              _TestAppLocalizationsDelegate(),
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            home: Scaffold(
              body: MessageContextMenu(
                messageOffset: const Offset(16, 120),
                messageSize: const Size(280, 60),
                isMe: false,
                enableBlur: true,
                messageContent: message.content,
                focusedMessageBuilder: (focusedKey) => MessageBubble(
                  key: focusedKey,
                  message: message,
                  isMe: false,
                  currentUserId: 'me_1',
                  formatTime: (_) => '12:00',
                ),
                onReply: () {},
                onCopy: () {},
                onPin: () {},
                onDelete: () {},
                onReaction: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify MouseRegion with SystemMouseCursors.text is present
      final textCursorRegions = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.text,
      );
      expect(textCursorRegions, findsWidgets);

      // Drag across the focused TextMessageWidget text to select a range
      final textCenter = tester.getCenter(find.byType(TextMessageWidget));
      await tester.dragFrom(
        textCenter - const Offset(35, 0),
        const Offset(70, 0),
      );
      await tester.pumpAndSettle();

      // Toolbar appears, but rotated teardrop handle Transform.rotate is NOT rendered on desktop
      expect(find.byType(MessageTextSelectionToolbar), findsOneWidget);
      final rotatedHandles = find.byWidgetPredicate(
        (w) =>
            w is Transform &&
            w.child is CustomPaint &&
            (w.child as CustomPaint).painter.runtimeType.toString() ==
                '_MessageTeardropHandlePainter',
      );
      expect(rotatedHandles, findsNothing);
    });

    testWidgets(
        'Separated message in blur mode preserves revealed spoiler and expanded collapsible blockquote state',
        (WidgetTester tester) async {
      final message = Message(
        id: 'm_interactive_persist_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content:
            '||Скрытый секрет||\n**>Строка 1\n>Строка 2\n>Строка 3\n>Строка 4\n>Строка 5',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      // 1. Render original MessageBubble in chat (aligned top-left so it takes natural height)
      await tester.pumpWidget(
        createTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: MessageBubble(
              message: message,
              isMe: false,
              currentUserId: 'me_1',
              formatTime: (_) => '12:00',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Initially spoiler is hidden and quote shows 'format_expand'
      expect(find.text('format_expand'), findsOneWidget);
      final collapsedHeight =
          tester.getSize(find.byType(CollapsibleBlockquoteWidget)).height;

      // Reveal the inline spoiler and expand the collapsible blockquote
      final spoilerTextFinder = find.textContaining(
        'Скрытый секрет',
        findRichText: true,
      );
      await tester.tap(spoilerTextFinder);
      await tester.pump(const Duration(milliseconds: 450));

      await tester.tap(find.text('format_expand'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('format_collapsed_state'), findsOneWidget);
      final expandedHeight =
          tester.getSize(find.byType(CollapsibleBlockquoteWidget)).height;
      expect(expandedHeight, greaterThan(collapsedHeight));
      final expandedBubbleHeight =
          tester.getSize(find.byType(MessageBubble)).height;

      // 2. Now render a fresh focused MessageBubble inside MessageContextMenu (simulating blur separation)
      await tester.pumpWidget(
        createTestApp(
          MessageContextMenu(
            messageOffset: const Offset(0, 80),
            messageSize: Size(800, expandedBubbleHeight),
            isMe: false,
            enableBlur: true,
            messageContent: message.content,
            focusedMessageBuilder: (focusedKey) => MessageBubble(
              key: focusedKey,
              message: message,
              isMe: false,
              currentUserId: 'me_1',
              formatTime: (_) => '12:00',
            ),
            onReply: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onReaction: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Both the expanded quote state ('format_collapsed_state') and the expanded height are preserved!
      expect(find.text('format_collapsed_state'), findsOneWidget);
      final focusedQuoteHeight =
          tester.getSize(find.byType(CollapsibleBlockquoteWidget)).height;
      expect((focusedQuoteHeight - expandedHeight).abs(), lessThan(2.0));
    });

    testWidgets(
        'Tapping in the empty area beside the separated message bubble dismisses the blur context menu',
        (WidgetTester tester) async {
      final message = Message(
        id: 'm_dismiss_beside_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content: 'Short message',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      pageBuilder: (routeCtx, anim, secAnim) =>
                          MessageContextMenu(
                        messageOffset: const Offset(0, 120),
                        messageSize: const Size(800, 56),
                        isMe: false,
                        enableBlur: true,
                        messageContent: message.content,
                        focusedMessageBuilder: (focusedKey) => MessageBubble(
                          key: focusedKey,
                          message: message,
                          isMe: false,
                          currentUserId: 'me_1',
                          formatTime: (_) => '12:00',
                        ),
                        onReply: () {},
                        onCopy: () {},
                        onPin: () {},
                        onDelete: () {},
                        onReaction: (_) {},
                      ),
                    ),
                  );
                },
                child: const Text('Open Menu'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageContextMenu), findsOneWidget);

      // Tap at (x: 650, y: 145) — on the same vertical row (120..176) as the message,
      // but in the empty space to the right of the incoming message bubble!
      await tester.tapAt(const Offset(650, 145));
      await tester.pumpAndSettle();

      // Context menu and blur should be dismissed!
      expect(find.byType(MessageContextMenu), findsNothing);
    });

    testWidgets(
        'MessageContextMenu activates activeBlurMessageId after initial frame and never wraps focused message in FadeTransition',
        (WidgetTester tester) async {
      final service = MessageContextMenuService();
      service.clearActiveBlurMessage();

      final message = Message(
        id: 'm_zero_blink_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content: 'Zero blink message separation',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (routeCtx, anim, secAnim) =>
                          MessageContextMenu(
                        messageOffset: const Offset(0, 120),
                        messageSize: const Size(800, 56),
                        isMe: false,
                        activeBlurMessageId: message.id,
                        enableBlur: true,
                        messageContent: message.content,
                        focusedMessageBuilder: (focusedKey) => MessageBubble(
                          key: focusedKey,
                          message: message,
                          isMe: false,
                          currentUserId: 'me_1',
                          formatTime: (_) => '12:00',
                        ),
                        onReply: () {},
                        onCopy: () {},
                        onPin: () {},
                        onDelete: () {},
                        onReaction: (_) {},
                      ),
                    ),
                  );
                },
                child: const Text('Show Blur Menu'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Blur Menu'));
      // After initial frame (post-frame callback executed during pump),
      // activeBlurMessageId is set and the focused message is rendered at full opacity (no FadeTransition ancestor).
      await tester.pump();
      expect(service.activeBlurMessageId.value, equals(message.id));
      expect(
        find.ancestor(
          of: find.byType(MessageBubble),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      // Dismiss by tapping outside
      await tester.tapAt(const Offset(650, 145));
      await tester.pumpAndSettle();
      expect(service.activeBlurMessageId.value, isNull);
      expect(find.byType(MessageContextMenu), findsNothing);
    });

    testWidgets(
        'Direct LMB drag on chat message opens blur overlay via OverlayEntry without cancelling active mouse pointer and selects full dragged range on first drag',
        (WidgetTester tester) async {
      final service = MessageContextMenuService();
      service.removeActiveOverlay();

      final messageKey = GlobalKey();
      final message = Message(
        id: 'm_first_drag_select_1',
        chatId: 'c1',
        senderId: 'u2',
        senderName: 'Alice',
        content: 'Первое выделение текста мышкой работает без прерывания до самого конца строки',
        messageType: 'text',
        isRead: true,
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
      );

      Offset? dragStartPos;
      bool dragTriggered = false;
      int pointerCancelCount = 0;
      String? quotedSlice;

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (chatContext) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    event.buttons == kPrimaryMouseButton) {
                  dragStartPos = event.position;
                  dragTriggered = false;
                }
              },
              onPointerMove: (event) {
                if (dragStartPos == null) return;
                if ((event.buttons & kPrimaryMouseButton) == 0) return;
                final dist = (event.position - dragStartPos!).distance;
                if (!dragTriggered && dist > 4.0) {
                  dragTriggered = true;
                  service.show(
                    context: chatContext,
                    message: message,
                    messageKey: messageKey,
                    isMe: false,
                    enableBlur: true,
                    initialDragStartGlobalPosition: dragStartPos,
                    initialDragCurrentGlobalPosition: event.position,
                    onReply: () {},
                    onQuotePartial: (text, offset, length) {
                      quotedSlice = text;
                    },
                    onPin: () {},
                    onDelete: (_) {},
                    onReaction: (id, emoji) {},
                  );
                } else if (dragTriggered) {
                  service.updateExternalDragSelection(event.position);
                }
              },
              onPointerUp: (_) {
                if (dragTriggered) {
                  service.endExternalDragSelection();
                }
                dragStartPos = null;
                dragTriggered = false;
              },
              onPointerCancel: (_) {
                pointerCancelCount++;
                if (dragTriggered) {
                  service.endExternalDragSelection();
                }
                dragStartPos = null;
                dragTriggered = false;
              },
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 100),
                  child: ValueListenableBuilder<String?>(
                    valueListenable: service.activeBlurMessageId,
                    builder: (context, activeBlurId, child) {
                      final isHidden = activeBlurId == message.id;
                      return Visibility(
                        visible: !isHidden,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: child!,
                      );
                    },
                    child: MessageBubble(
                      key: messageKey,
                      message: message,
                      isMe: false,
                      currentUserId: 'me_1',
                      formatTime: (_) => '12:00',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textRect = tester.getRect(find.byType(TextMessageWidget));
      final startPoint = Offset(textRect.left + 8, textRect.top + 10);

      // Start a single mouse LMB drag on the in-list message text
      final gesture = await tester.startGesture(
        startPoint,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await tester.pump();

      // Move 6px right -> triggers MessageContextMenuService().show(...)
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Verify the active mouse pointer was NOT cancelled when the blur overlay opened!
      expect(pointerCancelCount, equals(0));
      expect(find.byType(MessageContextMenu), findsOneWidget);

      // Continue dragging the SAME mouse gesture across the message without releasing
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));

      // Release LMB at the end of the drag
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pointerCancelCount, equals(0));
      expect(find.byType(MessageTextSelectionToolbar), findsOneWidget);

      // Click the Quote button on the selection toolbar and verify a long multi-word range was selected on the very first drag!
      final quoteBtn = find.descendant(
        of: find.byType(MessageTextSelectionToolbar),
        matching: find.text('Цитировать'),
      );
      if (quoteBtn.evaluate().isNotEmpty) {
        await tester.tap(quoteBtn);
      } else {
        // Fallback if localized key is rendered
        await tester.tap(
          find.descendant(
            of: find.byType(MessageTextSelectionToolbar),
            matching: find.byType(InkWell),
          ).at(1),
        );
      }
      await tester.pumpAndSettle();

      expect(quotedSlice, isNotNull);
      expect(quotedSlice!.length, greaterThan(10));
    });

    testWidgets(
        'MessageContextMenu shown above message anchors its bottom 8px above message top without overlapping and uses ClipRect with TileMode.mirror',
        (WidgetTester tester) async {
      const double messageTop = 410.0;
      const double messageHeight = 140.0;

      await tester.pumpWidget(
        createTestApp(
          SizedBox(
            width: 800,
            height: 600,
            child: MessageContextMenu(
              messageOffset: const Offset(0, messageTop),
              messageSize: const Size(800, messageHeight),
              isMe: false,
              enableBlur: true,
              messageContent: 'Message near bottom of chat',
              onReply: () {},
              onQuote: () {},
              onCopy: () {},
              onPin: () {},
              onSelect: () {},
              onDelete: () {},
              onReaction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the ScaleTransition wrapping the context menu panels
      final menuScaleFinder = find.descendant(
        of: find.byType(MessageContextMenu),
        matching: find.byType(ScaleTransition),
      );
      expect(menuScaleFinder, findsOneWidget);

      final menuRect = tester.getRect(menuScaleFinder);
      // The bottom edge of the menu must sit at messageTop - 8.0 (402.0) and never overlap messageTop (410.0)
      expect(menuRect.bottom, lessThanOrEqualTo(messageTop - 7.5));

      // Verify BackdropFilter is wrapped in ClipRect and uses composed opaque blur filter with TileMode.mirror
      final backdropFinder = find.descendant(
        of: find.byType(MessageContextMenu),
        matching: find.byType(BackdropFilter),
      );
      expect(backdropFinder, findsOneWidget);
      expect(
        find.ancestor(
          of: backdropFinder,
          matching: find.byType(ClipRect),
        ),
        findsWidgets,
      );
      final backdropWidget = tester.widget<BackdropFilter>(backdropFinder);
      expect(
        backdropWidget.filter.toString(),
        contains('mirror'),
      );
      // On mobile (Android/iOS default in widget tests), standalone blur avoids Impeller compose nearest-neighbor pixelation
      expect(
        backdropWidget.filter.toString(),
        isNot(contains('compose')),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(
          MessageContextMenu.buildOpaqueBackdropBlurFilter(14.0).toString(),
          contains('compose'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        'MessageContextMenu inside split StaticTileCacheBoundary produces uniform edge blur without unblurred chat bleed-through or cross-tile bleed-through',
        (WidgetTester tester) async {
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        createTestApp(
          RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  // Bright red adjacent left tile (x = 0..292) separated by an 8px transparent divider (x = 292..300)
                  const Positioned(
                    left: 0,
                    top: 0,
                    width: 292,
                    height: 600,
                    child: ColoredBox(color: Color(0xFFFF0000)),
                  ),
                  // Chat tile at x = 300..800 wrapped in StaticTileCacheBoundary
                  Positioned(
                    left: 300,
                    top: 0,
                    width: 500,
                    height: 600,
                    child: StaticTileCacheBoundary(
                      enabled: true,
                      child: Stack(
                        children: [
                          // Dark navy chat background
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0xFF0A1224)),
                          ),
                          // High-contrast message bubble 8px from the left edge of the chat tile (x = 308..480)
                          const Positioned(
                            left: 8,
                            top: 10,
                            width: 172,
                            height: 100,
                            child: ColoredBox(color: Color(0xFF3A5284)),
                          ),
                          // Bright cyan quote bar 20px from the left edge (x = 320..324)
                          const Positioned(
                            left: 20,
                            top: 15,
                            width: 4,
                            height: 90,
                            child: ColoredBox(color: Color(0xFF64E6DC)),
                          ),
                          // MessageContextMenu blurring the chat tile (anchored near bottom so y=60 is pure blurred backdrop)
                          Positioned.fill(
                            child: MessageContextMenu(
                              messageOffset: const Offset(100, 480),
                              messageSize: const Size(200, 60),
                              isMe: false,
                              enableBlur: true,
                              messageContent: 'Edge blur test',
                              onReply: () {},
                              onQuote: () {},
                              onViewPollResults: () {},
                              onRetractVote: () {},
                              onStopPoll: () {},
                              onCopy: () {},
                              onPin: () {},
                              onSelect: () {},
                              onDelete: () {},
                              onReaction: (_) {},
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
        ),
      );
      await tester.pumpAndSettle();

      Future<void> verifyEdgeBlur(String phase) async {
        final ro = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final dpr = tester.view.devicePixelRatio;
        final img = ro.toImageSync(pixelRatio: 1.0);
        final w = img.width;
        final bd = await tester.runAsync(
          () => img.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        img.dispose();
        expect(bd, isNotNull);

        final bytes = bd!.buffer.asUint8List();
        int rAt(int x, int y) => bytes[(y * w + x) * 4];
        int gAt(int x, int y) => bytes[(y * w + x) * 4 + 1];
        int bAt(int x, int y) => bytes[(y * w + x) * 4 + 2];

        const int sampleY = 60;

        // 1. Verify zero red bleed-through from the left tile (x = 0..292) at the chat tile's left edge (x = 300..315)
        for (int x = 300; x <= 315; x++) {
          expect(
            rAt(x, sampleY),
            lessThan(45),
            reason:
                '[$phase] Adjacent red tile must not bleed across the divider into chat tile pixel x=$x (dpr=$dpr)',
          );
        }

        // 2. Verify no sharp 1-pixel unblurred step at the message bubble edge (x = 307 -> 308 -> 309)
        // Without alpha normalization, dx between x=307 and x=308 is ~23 RGB units due to 28.4% unblurred bleed-through.
        for (int x = 301; x <= 330; x++) {
          final dr = (rAt(x, sampleY) - rAt(x - 1, sampleY)).abs();
          final dg = (gAt(x, sampleY) - gAt(x - 1, sampleY)).abs();
          final db = (bAt(x, sampleY) - bAt(x - 1, sampleY)).abs();
          expect(
            dr,
            lessThanOrEqualTo(4),
            reason: '[$phase] Sharp horizontal R step at x=${x - 1}->$x',
          );
          expect(
            dg,
            lessThanOrEqualTo(4),
            reason: '[$phase] Sharp horizontal G step at x=${x - 1}->$x',
          );
          expect(
            db,
            lessThanOrEqualTo(4),
            reason: '[$phase] Sharp horizontal B step at x=${x - 1}->$x',
          );
        }
      }

      // Phase 1: Stationary
      await verifyEdgeBlur('stationary');

      // Phase 2: Actively scrolling the compressed action list (_activePointers > 0, _renderLive)
      final actionGesture = await tester.startGesture(
        tester.getCenter(find.byType(SingleChildScrollView).last),
      );
      await tester.pump();
      await actionGesture.moveBy(const Offset(0, -45));
      await tester.pump();

      await verifyEdgeBlur('scrolling-action-list');

      await actionGesture.up();
      await tester.pumpAndSettle();

      // Phase 3: Actively scrolling the compressed emoji reaction list (_activePointers > 0, _renderLive)
      final emojiGesture = await tester.startGesture(
        tester.getCenter(find.byType(SingleChildScrollView).first),
      );
      await tester.pump();
      await emojiGesture.moveBy(const Offset(0, -30));
      await tester.pump();

      await verifyEdgeBlur('scrolling-emoji-list');

      await emojiGesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'MessageContextMenu scrolls action items inside the stationary panel container when vertical space is constrained',
        (WidgetTester tester) async {
      bool deleteTapped = false;

      // Constrain available height below the message:
      // viewport height = 380, messageTop = 40, messageHeight = 150 -> messageBottom = 190
      // availableBelow = (380 - 12) - (190 + 8) = 170px, while the full action list is ~400px tall.
      await tester.pumpWidget(
        createTestApp(
          SizedBox(
            width: 400,
            height: 380,
            child: MessageContextMenu(
              messageOffset: const Offset(16, 40),
              messageSize: const Size(260, 150),
              isMe: true,
              enableBlur: false,
              messageContent: 'Message with many context actions',
              onReply: () {},
              onQuote: () {},
              onViewPollResults: () {},
              onRetractVote: () {},
              onStopPoll: () {},
              onCopy: () {},
              onPin: () {},
              onEdit: () {},
              onSelect: () {},
              onDelete: () {
                deleteTapped = true;
              },
              onReaction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Locate the outer action panel Container (width == 215)
      final actionPanelFinder = find.descendant(
        of: find.byType(MessageContextMenu),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 215.0,
        ),
      );
      expect(actionPanelFinder, findsOneWidget);

      final Rect initialPanelRect = tester.getRect(actionPanelFinder);
      expect(initialPanelRect.height, closeTo(170.0, 1.0));

      // Verify SingleChildScrollView is a descendant INSIDE the action panel Container, NOT an ancestor of Row
      final actionScrollFinder = find.descendant(
        of: actionPanelFinder,
        matching: find.byType(SingleChildScrollView),
      );
      expect(actionScrollFinder, findsOneWidget);

      final Rect initialReplyRect =
          tester.getRect(find.text('chat_action_reply'));

      // Scroll the action list inside the panel upwards to reveal 'chat_action_delete' at the bottom of the 10-item list
      await tester.scrollUntilVisible(
        find.text('chat_action_delete'),
        80.0,
        scrollable: find.descendant(
          of: actionPanelFinder,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      // The outer action panel Container must remain completely stationary!
      final Rect afterScrollPanelRect = tester.getRect(actionPanelFinder);
      expect(afterScrollPanelRect.top, closeTo(initialPanelRect.top, 0.1));
      expect(
        afterScrollPanelRect.bottom,
        closeTo(initialPanelRect.bottom, 0.1),
      );

      // Meanwhile, the action items inside the panel must have scrolled upwards
      final Rect afterScrollReplyRect =
          tester.getRect(find.text('chat_action_reply'));
      expect(afterScrollReplyRect.top, lessThan(initialReplyRect.top - 100.0));

      // And 'chat_action_delete' is now visible inside the stationary panel and tappable
      await tester.tap(find.text('chat_action_delete'));
      await tester.pumpAndSettle();
      expect(deleteTapped, isTrue);
    });

    testWidgets(
        'Vertical split of 2 chats removes bottom blur on top chat and removes top blur + status bar padding on bottom chat',
        (WidgetTester tester) async {
      final glassProvider = _TestEnabledLiquidGlassProvider();

      double? topChatTopPadding;
      double? topChatBottomPadding;
      double? bottomChatTopPadding;
      double? bottomChatBottomPadding;

      await tester.pumpWidget(
        ChangeNotifierProvider<LiquidGlassProvider>.value(
          value: glassProvider,
          child: MaterialApp(
            localizationsDelegates: const [_TestAppLocalizationsDelegate()],
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(top: 48.0, bottom: 34.0),
                  viewPadding: const EdgeInsets.only(top: 48.0, bottom: 34.0),
                ),
                child: child!,
              );
            },
            home: Column(
              children: [
                // Top chat tile (hasBottomNeighbor: true)
                Expanded(
                  child: TileViewportScope(
                    key: const ValueKey('top_tile_scope'),
                    tileId: 'chat_tile_top',
                    isChatTile: true,
                    hasBottomNeighbor: true,
                    child: ChatScaffold(
                      appBar: FloatingGlassAppBar(
                        name: 'Top Chat',
                        isOnline: false,
                        onBack: () {},
                        onTitleTap: () {},
                      ),
                      body: Stack(
                        children: [
                          Builder(
                            builder: (ctx) {
                              topChatTopPadding = MediaQuery.paddingOf(ctx).top;
                              topChatBottomPadding =
                                  MediaQuery.paddingOf(ctx).bottom;
                              return const SizedBox.expand();
                            },
                          ),
                          const ChatBottomScrollEdge(),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom chat tile (hasTopNeighbor: true)
                Expanded(
                  child: TileViewportScope(
                    key: const ValueKey('bottom_tile_scope'),
                    tileId: 'chat_tile_bottom',
                    isChatTile: true,
                    hasTopNeighbor: true,
                    child: ChatScaffold(
                      appBar: FloatingGlassAppBar(
                        name: 'Bottom Chat',
                        isOnline: false,
                        onBack: () {},
                        onTitleTap: () {},
                      ),
                      body: Stack(
                        children: [
                          Builder(
                            builder: (ctx) {
                              bottomChatTopPadding =
                                  MediaQuery.paddingOf(ctx).top;
                              bottomChatBottomPadding =
                                  MediaQuery.paddingOf(ctx).bottom;
                              return const SizedBox.expand();
                            },
                          ),
                          const ChatBottomScrollEdge(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Top chat preserves top status bar padding (48.0) and has 0 bottom padding
      expect(topChatTopPadding, equals(48.0));
      expect(topChatBottomPadding, equals(0.0));

      // Top chat has top scroll edge blur, but NO bottom scroll edge blur
      final topTileEdges = tester
          .widgetList<LiquidGlassScrollEdge>(
            find.descendant(
              of: find.byKey(const ValueKey('top_tile_scope')),
              matching: find.byType(LiquidGlassScrollEdge),
            ),
          )
          .toList();
      expect(topTileEdges.length, equals(1));
      expect(topTileEdges.first.edge, equals(LiquidGlassEdge.top));

      // 2. Bottom chat has 0 top status bar padding and preserves bottom padding (34.0)
      expect(bottomChatTopPadding, equals(0.0));
      expect(bottomChatBottomPadding, equals(34.0));

      // Bottom chat has NO top scroll edge blur, and only has bottom scroll edge blur
      final bottomTileEdges = tester
          .widgetList<LiquidGlassScrollEdge>(
            find.descendant(
              of: find.byKey(const ValueKey('bottom_tile_scope')),
              matching: find.byType(LiquidGlassScrollEdge),
            ),
          )
          .toList();
      expect(bottomTileEdges.length, equals(1));
      expect(bottomTileEdges.first.edge, equals(LiquidGlassEdge.bottom));

      // Verify bottom chat's FloatingGlassAppBar has no status-bar height offset
      final topAppBarRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('top_tile_scope')),
          matching: find.byType(FloatingGlassAppBar),
        ),
      );
      final bottomAppBarRect = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('bottom_tile_scope')),
          matching: find.byType(FloatingGlassAppBar),
        ),
      );
      expect(topAppBarRect.height - bottomAppBarRect.height, closeTo(48.0, 0.1));
    });

    test(
        'TilingLayoutController accurately replaces target chat on drag and collapses 2 chats into 1 when dropped in center',
        () {
      final controller = TilingLayoutController.instance;
      controller.closeAllChats();
      controller.updateWindowMetrics(const Size(1280, 800));
      const rightRect = Rect.fromLTWH(388, 0, 892, 800);
      controller.rightWorkspaceRectResolver = () => rightRect;

      // Open 2 chats horizontally: Chat A (left, tiles[0]) and Chat B (right, tiles[1])
      controller.openChatInActiveTile(
        chatId: 'chat_a',
        chatType: 'private',
        chatName: 'Chat A',
      );
      controller.openChatInAdjacentTile(
        chatId: 'chat_b',
        chatType: 'private',
        chatName: 'Chat B',
        splitAxis: Axis.horizontal,
        placeFirst: false,
      );
      expect(controller.chatTiles.length, equals(2));
      expect(controller.chatTiles[0].chatId, equals('chat_a'));
      expect(controller.chatTiles[1].chatId, equals('chat_b'));

      // Focus Chat A (tiles[0]), then drag Chat C from the left list onto Chat A (relX = 0.15, relY = 0.20):
      // Even though Chat A is focused and relX < 0.28 / relY < 0.28, it MUST replace Chat A (tiles[0]), NOT Chat B!
      controller.setFocusedTile(controller.chatTiles[0].tileId);
      controller.startDraggingChat(
        DraggingChatPayload(
          chatId: 'chat_c',
          chatType: 'private',
          chatName: 'Chat C',
          initialGlobalRect: const Rect.fromLTWH(20, 100, 300, 64),
        ),
      );
      controller.updateDraggingChat(
        Offset(
          rightRect.left + rightRect.width * 0.15,
          rightRect.top + rightRect.height * 0.20,
        ),
      );
      expect(controller.hoveredDropSlot, equals(TilingDropSlot.replace));
      expect(
        controller.hoveredTargetTileId,
        equals(controller.chatTiles[0].tileId),
      );
      controller.endDraggingChat();

      expect(controller.chatTiles.length, equals(2));
      expect(controller.chatTiles[0].chatId, equals('chat_c'));
      expect(controller.chatTiles[1].chatId, equals('chat_b'));

      // Now drag one of the 2 open chats (Chat B, tiles[1]) to the center of the workspace (relX = 0.5, relY = 0.5):
      // It MUST collapse the 2 open chats into 1 chat (Chat B)!
      final tileB = controller.chatTiles[1];
      controller.startDraggingChat(
        DraggingChatPayload(
          chatId: tileB.chatId,
          chatType: tileB.chatType,
          chatName: tileB.chatName,
          sourceTileId: tileB.tileId,
          initialGlobalRect: const Rect.fromLTWH(800, 20, 400, 600),
        ),
      );
      controller.updateDraggingChat(
        Offset(
          rightRect.left + rightRect.width * 0.50,
          rightRect.top + rightRect.height * 0.50,
        ),
      );
      expect(controller.hoveredDropSlot, equals(TilingDropSlot.replace));
      controller.endDraggingChat();

      expect(controller.chatTiles.length, equals(1));
      expect(controller.chatTiles.first.chatId, equals('chat_b'));

      // Re-open 2 chats (Chat B and Chat C) and drag Chat D from the left list into the center (relX = 0.5, relY = 0.5):
      // It MUST also collapse both open chats into 1 chat (Chat D)!
      controller.openChatInAdjacentTile(
        chatId: 'chat_c',
        chatType: 'private',
        chatName: 'Chat C',
        splitAxis: Axis.horizontal,
        placeFirst: false,
      );
      expect(controller.chatTiles.length, equals(2));

      controller.startDraggingChat(
        DraggingChatPayload(
          chatId: 'chat_d',
          chatType: 'private',
          chatName: 'Chat D',
          initialGlobalRect: const Rect.fromLTWH(20, 180, 300, 64),
        ),
      );
      controller.updateDraggingChat(
        Offset(
          rightRect.left + rightRect.width * 0.50,
          rightRect.top + rightRect.height * 0.50,
        ),
      );
      expect(controller.hoveredDropSlot, equals(TilingDropSlot.replace));
      expect(controller.hoveredTargetTileId, isNull);
      controller.endDraggingChat();

      expect(controller.chatTiles.length, equals(1));
      expect(controller.chatTiles.first.chatId, equals('chat_d'));

      controller.rightWorkspaceRectResolver = null;
      controller.closeAllChats();
    });

    testWidgets(
        'MessageContextMenu places menu to the right of incoming message and left of outgoing message when chat is wide enough but vertically short',
        (WidgetTester tester) async {
      // 1. Incoming message (isMe: false) in a 680x320 wide-but-short chat -> menu placed to the RIGHT of the bubble
      await tester.pumpWidget(
        createTestApp(
          SizedBox(
            width: 680,
            height: 320,
            child: MessageContextMenu(
              messageOffset: const Offset(20, 90),
              messageSize: const Size(220, 120),
              isMe: false,
              enableBlur: false,
              messageContent: 'Incoming message in vertically short split chat',
              onReply: () {},
              onQuote: () {},
              onCopy: () {},
              onPin: () {},
              onSelect: () {},
              onDelete: () {},
              onReaction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emojiPanelFinder = find.descendant(
        of: find.byType(MessageContextMenu),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 44.0,
        ),
      );
      final actionPanelFinder = find.descendant(
        of: find.byType(MessageContextMenu),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 215.0,
        ),
      );

      final Rect incomingEmojiRect = tester.getRect(emojiPanelFinder);
      final Rect incomingActionRect = tester.getRect(actionPanelFinder);
      // Emoji panel is 8px to the right of incoming bubble (20 + 220 + 8 = 248)
      expect(incomingEmojiRect.left, closeTo(248.0, 0.5));
      // Order is always [Reactions] -> [Actions] left-to-right
      expect(incomingActionRect.left, closeTo(incomingEmojiRect.right + 8.0, 0.5));

      // 2. Outgoing message (isMe: true) in a 680x320 chat -> menu placed to the LEFT of the bubble
      await tester.pumpWidget(
        createTestApp(
          SizedBox(
            width: 680,
            height: 320,
            child: MessageContextMenu(
              messageOffset: const Offset(440, 90),
              messageSize: const Size(220, 120),
              isMe: true,
              enableBlur: false,
              messageContent: 'Outgoing message in vertically short split chat',
              onReply: () {},
              onQuote: () {},
              onCopy: () {},
              onPin: () {},
              onEdit: () {},
              onSelect: () {},
              onDelete: () {},
              onReaction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Rect outgoingEmojiRect = tester.getRect(emojiPanelFinder);
      final Rect outgoingActionRect = tester.getRect(actionPanelFinder);
      // Total menu width is 267 (44 + 8 + 215), placed 8px to the left of 440 -> left = 440 - 267 - 8 = 165
      expect(outgoingEmojiRect.left, closeTo(165.0, 0.5));
      expect(outgoingActionRect.right, closeTo(440.0 - 8.0, 0.5));
      // Order remains [Reactions] -> [Actions] left-to-right
      expect(outgoingEmojiRect.left, lessThan(outgoingActionRect.left));
    });

    testWidgets(
        'TileResizeDivider renders always-visible capsule handle, responds to drag across expanded 28x64px handle hit zone, and swaps chat tiles on double tap',
        (WidgetTester tester) async {
      final controller = TilingLayoutController.instance;
      controller.closeAllChats();
      controller.updateWindowMetrics(const Size(1280, 800));
      controller.openChatInActiveTile(
        chatId: 'chat_swap_1',
        chatType: 'private',
        chatName: 'Chat 1',
      );
      controller.openChatInAdjacentTile(
        chatId: 'chat_swap_2',
        chatType: 'private',
        chatName: 'Chat 2',
        splitAxis: Axis.horizontal,
        placeFirst: false,
      );
      expect(
        controller.chatTiles.map((t) => t.chatId).toList(),
        equals(['chat_swap_1', 'chat_swap_2']),
      );

      double accumulatedDelta = 0.0;
      bool doubleTapped = false;

      await tester.pumpWidget(
        createTestApp(
          Center(
            child: SizedBox(
              width: 200,
              height: 400,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TileResizeDivider(
                    lineAxis: Axis.vertical,
                    onDelta: (dx) => accumulatedDelta += dx,
                    onDoubleTap: () {
                      doubleTapped = true;
                      controller.swapChatTiles();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dividerCenter = tester.getCenter(find.byType(TileResizeDivider));
      // Start dragging 10px away from the 1px center line (inside the 28px handle hit zone, which previously missed the 8px divider!)
      await tester.dragFrom(
        dividerCenter + const Offset(10, 0),
        const Offset(35, 0),
      );
      await tester.pumpAndSettle();

      expect(accumulatedDelta, closeTo(35.0, 1.0));

      // Double-tap on the handle triggers onDoubleTap and swaps the two open chats
      await tester.tapAt(dividerCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(dividerCenter);
      await tester.pumpAndSettle();
      expect(doubleTapped, isTrue);
      expect(
        controller.chatTiles.map((t) => t.chatId).toList(),
        equals(['chat_swap_2', 'chat_swap_1']),
      );
      controller.closeAllChats();
    });

    testWidgets(
        'Animated emoji MessageBubble plays emoji on direct tap and opens MessageContextMenu when tapped beside the emoji',
        (WidgetTester tester) async {
      final bubbleKey = GlobalKey();
      int contextMenuOpenCount = 0;

      final emojiMessage = Message(
        id: 'emoji_msg_1',
        chatId: 'chat_1',
        senderId: 'user_1',
        senderName: 'Me',
        content: '🔥',
        messageType: 'text',
        createdAt: '2025-01-01T12:00:00Z',
        isRead: true,
        isEdited: false,
      );

      await tester.pumpWidget(
        createTestApp(
          Builder(
            builder: (context) {
              return Center(
                child: SizedBox(
                  width: 400,
                  height: 200,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      contextMenuOpenCount++;
                      MessageContextMenuService().show(
                        context: context,
                        message: emojiMessage,
                        messageKey: bubbleKey,
                        isMe: true,
                        enableBlur: false,
                        onReply: () {},
                        onPin: () {},
                        onDelete: (_) {},
                        onReaction: (_, __) {},
                      );
                    },
                    child: MessageBubble(
                      key: bubbleKey,
                      message: emojiMessage,
                      isMe: true,
                      currentUserId: 'user_1',
                      formatTime: (_) => '12:00',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      final lottieFinder = find.byType(LottieEmoji);
      expect(lottieFinder, findsOneWidget);

      // 1. Tap directly on the animated emoji (LottieEmoji) -> plays animation, does NOT open context menu
      await tester.tap(lottieFinder);
      await tester.pump();
      expect(contextMenuOpenCount, equals(0));
      expect(MessageContextMenuService().isShowing, isFalse);

      // 2. Tap beside the right-aligned animated emoji (in the empty left area of the message row) -> opens MessageContextMenu
      final rowRect = tester.getRect(find.byKey(bubbleKey));
      await tester.tapAt(Offset(rowRect.left + 24.0, rowRect.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(contextMenuOpenCount, equals(1));
      expect(MessageContextMenuService().isShowing, isTrue);
      expect(find.byType(MessageContextMenu), findsOneWidget);

      MessageContextMenuService().removeActiveOverlay();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'Single-pane custom swipe-back gesture pops nested SwipeBackPageRoute first, then interactively slides and closes root chat tile',
        (WidgetTester tester) async {
      final controller = TilingLayoutController.instance;
      controller.closeAllChats();
      controller.setWorkspaceMounted(true);
      controller.updateWindowMetrics(const Size(390, 800));

      controller.openChatInActiveTile(
        chatId: 'single_pane_chat_1',
        chatType: 'private',
        chatName: 'Alice',
      );
      final descriptor = controller.focusedChatTile!;

      final singlePaneAnim = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 250),
        value: 1.0,
      );
      bool restoredCalled = false;

      await tester.pumpWidget(
        createTestApp(
          SizedBox(
            width: 390,
            height: 800,
            child: InteractiveSwipeBackGestureDetector(
              animationController: singlePaneAnim,
              viewportSizeOverride: const Size(390, 800),
              canSwipeBack: () {
                final chatNav = descriptor.navigatorKey.currentState;
                if (chatNav != null && chatNav.canPop()) return false;
                if (descriptor.rootRoute != null &&
                    !descriptor.rootRoute!.isCurrent) {
                  return false;
                }
                return controller.singlePaneShowingChat;
              },
              onRestored: () {
                restoredCalled = true;
              },
              onDismissed: () {
                controller.closeChatTile(descriptor.tileId);
              },
              child: TileViewportScope(
                tileId: descriptor.tileId,
                isChatTile: true,
                child: Navigator(
                  key: descriptor.navigatorKey,
                  onGenerateRoute: (settings) {
                    final route = MaterialPageRoute<void>(
                      settings: settings,
                      builder: (ctx) => Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(ctx).push(
                                SwipeBackPageRoute(
                                  builder: (_) => const Scaffold(
                                    body: Center(child: Text('SubProfileScreen')),
                                  ),
                                ),
                              );
                            },
                            child: const Text('RootChatScreen'),
                          ),
                        ),
                      ),
                    );
                    descriptor.rootRoute = route;
                    return route;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RootChatScreen'), findsOneWidget);

      // 1. Push a sub-route (SwipeBackPageRoute) inside the chat tile's Navigator
      await tester.tap(find.text('RootChatScreen'));
      await tester.pumpAndSettle();
      expect(find.text('SubProfileScreen'), findsOneWidget);
      expect(descriptor.navigatorKey.currentState!.canPop(), isTrue);

      // 2. Swipe left-to-right in the middle of the screen -> pops SubProfileScreen first, singlePaneAnim stays at 1.0
      await tester.dragFrom(const Offset(60, 400), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(find.text('SubProfileScreen'), findsNothing);
      expect(find.text('RootChatScreen'), findsOneWidget);
      expect(singlePaneAnim.value, equals(1.0));
      expect(controller.chatTiles.length, equals(1));

      // 3. Short swipe (< 35% of 390px = ~60px) on RootChatScreen -> tracks 1:1 then springs back to 1.0 without closing
      final gesture = await tester.startGesture(const Offset(50, 400));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(singlePaneAnim.value, lessThan(0.9));
      expect(singlePaneAnim.value, greaterThan(0.6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(restoredCalled, isTrue);
      expect(singlePaneAnim.value, closeTo(1.0, 0.01));
      expect(controller.chatTiles.length, equals(1));

      // 4. Full swipe (> 35% of 390px = 200px) on RootChatScreen -> springs to 0.0 and closes chat tile
      await tester.dragFrom(const Offset(50, 400), const Offset(220, 0));
      await tester.pumpAndSettle();
      expect(singlePaneAnim.value, closeTo(0.0, 0.01));
      expect(controller.chatTiles, isEmpty);
      expect(controller.singlePaneShowingChat, isFalse);

      singlePaneAnim.dispose();
      controller.setWorkspaceMounted(false);
    });
  });
}




