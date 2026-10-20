import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/name_color_preset.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/utils/date_time_utils.dart';
import 'package:theaver/widgets/chat/message_reply_info.dart';
import 'package:theaver/widgets/chat/reply_preview_bar.dart';
import 'package:theaver/widgets/profile/reply_strip_painter.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/message_status_widget.dart';
import 'package:theaver/widgets/message/text_message_widget.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(super.locale, this.translations);

  @override
  String translate(String key) => translations[key] ?? key;
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  final Map<String, String> translations;
  const _TestAppLocalizationsDelegate([this.translations = const {}]);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
      _TestAppLocalizations(locale, translations),
    );
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

const Map<String, String> _kTranslations = {
  'chat_reply_you': 'Вы',
  'chat_reply_to': '{name}',
  'chat_message_type_voice': 'Голосовое сообщение',
  'chat_message_type_video': 'Видеосообщение',
  'chat_message_type_file': 'Файл',
  'chat_message_type_photo': 'Фотография',
};

Widget buildTestApp(Widget child, {ProfileThemeProvider? themeProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileThemeProvider>(
        create: (_) => themeProvider ?? ProfileThemeProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate(_kTranslations),
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
  group('Point 2.1 Reply Preview and Truncation Tests', () {
    testWidgets('MessageReplyInfo truncates long text and appends ...',
        (WidgetTester tester) async {
      const longText =
          'Это очень длинное сообщение, которое должно обязательно обрезаться многоточием на конце при отображении в блоке цитаты бабла сообщения';
      const reply = ReplyInfo(
        messageId: '100',
        senderId: 'user_2',
        senderName: 'Иван',
        content: longText,
        messageType: 'text',
      );

      await tester.pumpWidget(
        buildTestApp(
          const MessageReplyInfo(
            replyInfo: reply,
            currentUserId: 'user_1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Иван'), findsOneWidget);
      // Verify preview text in RichText ends with ...
      expect(
        find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText().contains('...'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MessageReplyInfo displays localized Вы when replying to oneself',
        (WidgetTester tester) async {
      const reply = ReplyInfo(
        messageId: '101',
        senderId: 'user_me',
        senderName: 'Моё Имя',
        content: 'Привет самому себе',
        messageType: 'text',
      );

      await tester.pumpWidget(
        buildTestApp(
          const MessageReplyInfo(
            replyInfo: reply,
            currentUserId: 'user_me',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Вы'), findsOneWidget);
    });

    testWidgets('MessageReplyInfo uses author appearance settings for styling',
        (WidgetTester tester) async {
      const reply = ReplyInfo(
        messageId: '102',
        senderId: 'user_friend',
        senderName: 'Алексей',
        content: 'Исходное сообщение друга',
        messageType: 'text',
        nameColorPresetId: 'name_orange',
        replyStripStyle: 'dualColor',
      );

      await tester.pumpWidget(
        buildTestApp(
          const MessageReplyInfo(
            replyInfo: reply,
            currentUserId: 'user_me',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Алексей'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('Алексей'));
      // Author name color should match name_orange preset (0xFFFB8C00)
      expect(textWidget.style?.color, const Color(0xFFFB8C00));

      // Check ReplyStripWidget properties
      final stripWidget = tester.widget<ReplyStripWidget>(find.byType(ReplyStripWidget));
      expect(stripWidget.preset.id, 'name_orange');
      expect(stripWidget.style, ReplyStripStyle.dualColor);
    });

    testWidgets('MessageReplyInfo falls back to name_red and solid strip for other user when preset is null',
        (WidgetTester tester) async {
      const reply = ReplyInfo(
        messageId: '103',
        senderId: 'user_other',
        senderName: 'Михаил',
        content: 'Сообщение с неуказанным стилем',
        messageType: 'text',
        nameColorPresetId: null,
        replyStripStyle: null,
      );

      await tester.pumpWidget(
        buildTestApp(
          const MessageReplyInfo(
            replyInfo: reply,
            currentUserId: 'user_me',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Михаил'), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text('Михаил'));
      // Fallback author name color must be name_red (0xFFE53935), NOT viewer preset
      expect(textWidget.style?.color, const Color(0xFFE53935));

      final stripWidget = tester.widget<ReplyStripWidget>(find.byType(ReplyStripWidget));
      expect(stripWidget.preset.id, 'name_red');
      expect(stripWidget.style, ReplyStripStyle.solid);
    });

    testWidgets('ReplyPreviewBar falls back to name_red and solid strip for other user when preset is null',
        (WidgetTester tester) async {
      final msg = Message(
        id: '201',
        chatId: 'chat_1',
        senderId: 'user_other',
        content: 'Сообщение в баре ответа с неуказанным стилем',
        messageType: 'text',
        isEdited: false,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        senderName: 'Ольга',
        senderNameColorId: null,
        senderReplyStripStyle: null,
      );

      await tester.pumpWidget(
        buildTestApp(
          ReplyPreviewBar(
            replyToMessage: msg,
            currentUserId: 'user_me',
            onClose: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Ольга'), findsOneWidget);
      final stripWidget = tester.widget<ReplyStripWidget>(find.byType(ReplyStripWidget));
      expect(stripWidget.preset.id, 'name_red');
      expect(stripWidget.style, ReplyStripStyle.solid);
    });

    testWidgets('ReplyPreviewBar applies author name and custom strip style',
        (WidgetTester tester) async {
      final msg = Message(
        id: '200',
        chatId: 'chat_1',
        senderId: 'user_author',
        content: 'Это текст сообщения автора',
        messageType: 'text',
        isEdited: false,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        senderName: 'Дмитрий',
        senderNameColorId: 'name_green',
        senderReplyStripStyle: 'candyCane',
      );

      await tester.pumpWidget(
        buildTestApp(
          ReplyPreviewBar(
            replyToMessage: msg,
            currentUserId: 'user_me',
            onClose: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Дмитрий'), findsOneWidget);
      final stripWidget = tester.widget<ReplyStripWidget>(find.byType(ReplyStripWidget));
      expect(stripWidget.preset.id, 'name_green');
      expect(stripWidget.style, ReplyStripStyle.candyCane);
    });
  });

  group('Timestamp UTC Format Tests', () {
    test('UTC ISO-8601 string parsing produces exact local time', () {
      const serverUtcString = '2026-09-07T14:30:00.000Z';
      final parsed = DateTimeUtils.parseUtcDateTime(serverUtcString);
      expect(parsed, isNotNull);

      final formatted = DateTimeUtils.formatTimeHHmm(serverUtcString);
      expect(formatted.isNotEmpty, isTrue);
    });
  });

  group('Profile & Name Color Presets Tests', () {
    test('ProfileColorPresets default is blue', () {
      final defaultPreset = ProfileColorPresets.getById('unknown_preset_id');
      expect(defaultPreset.id, 'blue');
      expect(defaultPreset.backgroundColor, const Color(0xFF2B82C9));
    });

    test('Custom dual gradient preset correctly reconstructs colors from ID', () {
      const color1 = Color(0xFF112233);
      const color2 = Color(0xFF445566);
      final custom = ProfileColorPreset.fromCustomGradient(color1, color2);
      expect(custom.id.startsWith('custom_grad_'), isTrue);

      final restored = ProfileColorPresets.getById(custom.id);
      expect(restored.isGradient, isTrue);
      expect(restored.gradientColors?[0].toARGB32(), color1.toARGB32());
      expect(restored.gradientColors?[1].toARGB32(), color2.toARGB32());
    });
  });

  group('MessageStatusWidget and Checkmarks Tests', () {
    testWidgets('MessageStatusWidget renders iconoir.DoubleCheck when isRead: true and isOutgoing: true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MessageStatusWidget(
            isRead: true,
            isOutgoing: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(iconoir.DoubleCheck), findsOneWidget);
      expect(find.byType(iconoir.Check), findsNothing);
    });

    testWidgets('MessageStatusWidget renders iconoir.Check when isRead: false and isOutgoing: true',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MessageStatusWidget(
            isRead: false,
            isOutgoing: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(iconoir.Check), findsOneWidget);
      expect(find.byType(iconoir.DoubleCheck), findsNothing);
    });

    testWidgets('MessageStatusWidget renders nothing when isOutgoing: false',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const MessageStatusWidget(
            isRead: true,
            isOutgoing: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(iconoir.DoubleCheck), findsNothing);
      expect(find.byType(iconoir.Check), findsNothing);
    });
  });

  group('MessageBubbleLayout Dynamic Metadata Fit Tests', () {
    testWidgets('MessageBubbleLayout places metadata in same row when single line fits',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: const MessageBubbleLayout(
              content: Text('Короткий текст'),
              metadata: Text('12:34'),
              text: 'Короткий текст',
              textStyle: TextStyle(fontSize: 16),
              metadataWidth: 32.0,
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleLayout = find.byType(MessageBubbleLayout);
      final size = tester.getSize(bubbleLayout);
      // Single line fits inline: bubble height <= 28.0 (no extra line)
      expect(size.height, lessThanOrEqualTo(28.0));
      final contentTop = tester.getTopLeft(find.text('Короткий текст')).dy;
      final metaTop = tester.getTopLeft(find.text('12:34')).dy;
      expect((contentTop - metaTop).abs(), lessThanOrEqualTo(8.0));
    });

    testWidgets('MessageBubbleLayout places metadata without extra row when multi-line has space on last line',
        (WidgetTester tester) async {
      // Long first line, short second line
      const multiLineText = 'Длинная первая строка текста которая точно перенесется\nКратко';
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: const MessageBubbleLayout(
              content: Text(multiLineText),
              metadata: Text('12:34'),
              text: multiLineText,
              textStyle: TextStyle(fontSize: 16),
              metadataWidth: 32.0,
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleLayout = find.byType(MessageBubbleLayout);
      final contentSize = tester.getSize(find.text(multiLineText));
      final bubbleSize = tester.getSize(bubbleLayout);
      // No extra row: bubble height equals content height
      expect(bubbleSize.height, equals(contentSize.height));
    });

    testWidgets('MessageBubbleLayout places metadata in separate row without stretching to maxContentWidth when last line is full',
        (WidgetTester tester) async {
      const text = 'Строка текста средней длины\nСтрока текста средней длины';
      await tester.pumpWidget(
        buildTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: const MessageBubbleLayout(
                content: Text(text),
                metadata: Text('12:34'),
                text: text,
                textStyle: TextStyle(fontSize: 16),
                metadataWidth: 60.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleLayout = find.byType(MessageBubbleLayout);
      final contentSize = tester.getSize(find.text(text));
      final bubbleSize = tester.getSize(bubbleLayout);
      // Extra row: bubble height > content height
      expect(bubbleSize.height, greaterThan(contentSize.height));
      // Ensure the bubble did NOT stretch to maxContentWidth (240), but matches content width
      expect(bubbleSize.width, equals(contentSize.width));
    });

    testWidgets('MessageBubbleLayout handles single line message with reply without layout overflow',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 350),
              child: const MessageBubbleLayout(
                content: Text('Привет!'),
                metadata: Text('12:34'),
                text: 'Привет!',
                textStyle: TextStyle(fontSize: 16),
                metadataWidth: 45.0,
                replyWidget: SizedBox(width: 180, height: 36, child: Text('Reply Header')),
                replyWidth: 180.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleLayout = find.byType(MessageBubbleLayout);
      final size = tester.getSize(bubbleLayout);
      // Size must be exactly reply width 180.0
      expect(size.width, 180.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MessageBubbleLayout places metadata inline for text with currency symbols',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: const MessageBubbleLayout(
              content: Text('\$100'),
              metadata: Text('12:34'),
              text: '\$100',
              textStyle: TextStyle(fontSize: 16),
              metadataWidth: 32.0,
            ),
          ),
        ),
      );
      await tester.pump();

      // Single line $100 fits inline with metadata, so height is single line (<= 28 px)
      final bubbleLayout = find.byType(MessageBubbleLayout);
      final size = tester.getSize(bubbleLayout);
      expect(size.height, lessThanOrEqualTo(28.0));
      final contentTop = tester.getTopLeft(find.text('\$100')).dy;
      final metaTop = tester.getTopLeft(find.text('12:34')).dy;
      expect((contentTop - metaTop).abs(), lessThanOrEqualTo(8.0));
    });

    testWidgets('MessageBubbleLayout expands bubble cleanly on last line without extra row when space is available',
        (WidgetTester tester) async {
      // Two equal lines of text: line 1 and line 2 have same width
      const twoLineText = 'Строка один\nСтрока два';
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: const MessageBubbleLayout(
              content: Text(twoLineText),
              metadata: Text('12:34'),
              text: twoLineText,
              textStyle: TextStyle(fontSize: 16),
              metadataWidth: 40.0,
            ),
          ),
        ),
      );
      await tester.pump();

      final bubbleLayout = find.byType(MessageBubbleLayout);
      final contentSize = tester.getSize(find.text(twoLineText));
      final bubbleSize = tester.getSize(bubbleLayout);
      // Since 350 maxWidth has plenty of room, metadata stays on line 2 (bubble height == content height)
      expect(bubbleSize.height, equals(contentSize.height));
      // Bubble expands horizontally just enough for metadata
      expect(bubbleSize.width, greaterThan(contentSize.width));
      expect(bubbleSize.width, lessThan(350));
    });

    testWidgets('MessageBubbleLayout never constricts content prematurely',
        (WidgetTester tester) async {
      // Line that fits naturally on one line within 350 maxWidth
      const singleLongLine = 'Сообщение';
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: const MessageBubbleLayout(
              content: Text(singleLongLine),
              metadata: Text('12:34'),
              text: singleLongLine,
              textStyle: TextStyle(fontSize: 16),
              metadataWidth: 35.0,
            ),
          ),
        ),
      );
      await tester.pump();

      final contentSize = tester.getSize(find.text(singleLongLine));
      // Content must remain single line (height <= 24 px)
      expect(contentSize.height, lessThanOrEqualTo(24.0));
      final bubbleLayout = find.byType(MessageBubbleLayout);
      final bubbleSize = tester.getSize(bubbleLayout);
      expect(bubbleSize.height, lessThanOrEqualTo(28.0));
    });

    testWidgets('MessageBubbleLayout places metadata on separate row when hasBlockElement is true',
        (WidgetTester tester) async {
      const codeText = 'var x = 42;';
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: const MessageBubbleLayout(
              content: Text(codeText),
              metadata: Text('12:34'),
              text: codeText,
              textStyle: TextStyle(fontSize: 16),
              hasBlockElement: true,
              metadataWidth: 40.0,
            ),
          ),
        ),
      );
      await tester.pump();

      final contentSize = tester.getSize(find.text(codeText));
      final bubbleLayout = find.byType(MessageBubbleLayout);
      final bubbleSize = tester.getSize(bubbleLayout);
      // Because hasBlockElement is true, metadata must be placed on a separate row below content
      expect(bubbleSize.height, greaterThan(contentSize.height));
    });

    testWidgets('MessageBubbleLayout does not overlap metadata with inline LaTeX formula',
        (WidgetTester tester) async {
      const latexMessage = r'Формула: $x_1 + y_2 = z_3$';
      await tester.pumpWidget(
        buildTestApp(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: const MessageBubbleLayout(
              content: TextMessageWidget(
                text: latexMessage,
                style: TextStyle(fontSize: 16),
              ),
              metadata: Text('12:34'),
              text: latexMessage,
              textStyle: TextStyle(fontSize: 16),
              metadataWidth: 38.0,
            ),
          ),
        ),
      );
      await tester.pump();

      final contentRect = tester.getRect(find.byType(TextMessageWidget));
      final metaRect = tester.getRect(find.text('12:34'));

      // Metadata must start to the right of the formula content, never overlapping it
      expect(metaRect.left, greaterThanOrEqualTo(contentRect.right));
      expect(contentRect.overlaps(metaRect), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}

