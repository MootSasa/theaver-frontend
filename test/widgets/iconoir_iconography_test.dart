import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/widgets/chat/classic_bottom_bar.dart';
import 'package:theaver/widgets/chat/floating_glass_app_bar.dart';
import 'package:theaver/widgets/chat/liquid_glass_bottom_bar.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/widgets/chat/message_context_menu.dart';
import 'package:theaver/widgets/chat/reply_preview_bar.dart';
import 'package:theaver/widgets/message/code_block_widget.dart';
import 'package:theaver/widgets/message/message_actions_widget.dart';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations(super.locale);
  @override
  String translate(String key, [Map<String, String>? params]) => key;
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

Widget createTestApp(Widget child, {Brightness brightness = Brightness.light}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LiquidGlassProvider()),
      ChangeNotifierProvider(create: (_) => ProfileThemeProvider()),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
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
  group('Iconoir Iconography Unification Tests', () {
    testWidgets('MessageContextMenu renders Iconoir icons for actions', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          Center(
            child: MessageContextMenu(
              messageOffset: Offset.zero,
              messageSize: const Size(200, 50),
              isMe: true,
              onReply: () {},
              onQuote: () {},
              onCopy: () {},
              onPin: () {},
              onEdit: () {},
              onDelete: () {},
              onReaction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.Reply), findsOneWidget);
      expect(find.byType(iconoir.Quote), findsOneWidget);
      expect(find.byType(iconoir.Copy), findsOneWidget);
      expect(find.byType(iconoir.Pin), findsOneWidget);
      expect(find.byType(iconoir.EditPencil), findsOneWidget);
      expect(find.byType(iconoir.Trash), findsOneWidget);
    });

    testWidgets('FloatingGlassAppBar renders Iconoir NavArrowLeft back button', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          FloatingGlassAppBar(
            name: 'Test Chat',
            isOnline: true,
            onBack: () {},
            onTitleTap: () {},
            onAvatarTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.NavArrowLeft), findsOneWidget);
    });

    testWidgets('LiquidGlassInputField renders Iconoir Emoji, Attachment, and Microphone/Send', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestApp(
          LiquidGlassInputField(
            enabled: true,
            controller: controller,
            hintText: 'Type...',
            onSend: () {},
            onAttach: () {},
            onVoice: () {},
            onEmoji: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially empty -> should have Emoji, Attachment, MicrophoneSolid
      expect(find.byType(iconoir.Emoji), findsOneWidget);
      expect(find.byType(iconoir.Attachment), findsOneWidget);
      expect(find.byType(iconoir.MicrophoneSolid), findsOneWidget);
      expect(find.byType(iconoir.SendDiagonalSolid), findsNothing);

      // When text is entered -> SendDiagonalSolid should replace MicrophoneSolid
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();

      expect(find.byType(iconoir.SendDiagonalSolid), findsOneWidget);
      expect(find.byType(iconoir.MicrophoneSolid), findsNothing);
    });

    testWidgets('ReplyPreviewBar renders Iconoir Quote and Xmark icons', (tester) async {
      final replyMessage = Message(
        id: '1',
        chatId: '100',
        senderId: 'user1',
        content: 'Replying to this',
        messageType: 'text',
        isEdited: false,
        createdAt: DateTime.now().toIso8601String(),
        senderName: 'Alice',
      );

      await tester.pumpWidget(
        createTestApp(
          ReplyPreviewBar(
            replyToMessage: replyMessage,
            isQuote: true,
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.Quote), findsOneWidget);
      expect(find.byType(iconoir.Xmark), findsOneWidget);
    });

    testWidgets('CodeBlockWidget renders Iconoir Copy icon', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const CodeBlockWidget(
            code: 'print("Hello, World!");',
            language: 'dart',
            isDark: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.Copy), findsOneWidget);
    });

    testWidgets('MessageActionsWidget renders Iconoir icons in popup menu', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          MessageActionsWidget(
            onAction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify PopupMenuButton uses iconoir.MoreVert
      expect(find.byType(iconoir.MoreVert), findsOneWidget);

      // Trigger popup
      await tester.tap(find.byType(PopupMenuButton<MessageAction>));
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.EditPencil), findsOneWidget);
      expect(find.byType(iconoir.Trash), findsOneWidget);
      expect(find.byType(iconoir.Forward), findsOneWidget);
    });

    testWidgets('ClassicBottomBar renders Iconoir tab icons and Plus add button', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          ClassicBottomBar(
            selectedIndex: 1,
            onTabSelected: (_) {},
            onAddTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.Settings), findsOneWidget);
      expect(find.byType(iconoir.ChatBubble), findsOneWidget);
      expect(find.byType(iconoir.Search), findsOneWidget);
      expect(find.byType(iconoir.Plus), findsOneWidget);
    });

    testWidgets('LiquidGlassBottomBar renders Iconoir tab icons and Plus add button', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          LiquidGlassBottomBar(
            selectedIndex: 1,
            onTabSelected: (_) {},
            onAddTap: () {},
            isLite: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(iconoir.Settings), findsOneWidget);
      expect(find.byType(iconoir.ChatBubble), findsOneWidget);
      expect(find.byType(iconoir.Search), findsOneWidget);
      expect(find.byType(iconoir.Plus), findsOneWidget);
    });
  });
}
