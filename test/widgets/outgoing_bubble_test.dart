import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/theme/chat_preview_card.dart';

void main() {
  testWidgets('Test outgoing message bubble in ListView with gradient theme', (WidgetTester tester) async {
    const testTheme = TheavTheme(
      id: 'test_theme',
      name: 'Test',
      author: 'Tester',
      isDark: false,
      wallpaper: TheavWallpaper(type: 'color', backgroundColor: Colors.white),
      palette: TheavPalette(
        primary: Colors.blue,
        onPrimary: Colors.white,
        background: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        appBarBackground: Colors.white,
        appBarForeground: Colors.black,
        chatBubbleOutgoing: Colors.blue,
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Colors.white70,
        chatBubbleIncoming: Colors.grey,
        chatBubbleIncomingText: Colors.black,
        chatBubbleIncomingSubtext: Colors.black54,
        chatDateBadge: Colors.grey,
        chatDateBadgeText: Colors.white,
        chatBubbleOutgoingGradient: [Colors.purple, Colors.blue],
      ),
    );

    final msg = Message(
      id: 'msg_1',
      chatId: 'chat_1',
      senderId: 'user_me',
      senderName: 'Me',
      content: 'Hello, this is an outgoing test message!',
      messageType: 'text',
      isEdited: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            TheavThemeExtension(
              palette: testTheme.palette,
              wallpaper: testTheme.wallpaper,
              bubbleRadius: 16.0,
            ),
          ],
        ),
        home: Scaffold(
          body: ListView(
            reverse: true,
            children: [
              MessageBubble(
                message: msg,
                isMe: true,
                currentUserId: 'user_me',
                formatTime: (ts) => '12:34',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Hello, this is an outgoing test message!'), findsOneWidget);
  });

  testWidgets('Test ChatPreviewCard with 3-color gradient', (WidgetTester tester) async {
    const testTheme = TheavTheme(
      id: 'test_theme_3',
      name: 'Test 3',
      author: 'Tester',
      isDark: false,
      wallpaper: TheavWallpaper(type: 'color', backgroundColor: Colors.white),
      palette: TheavPalette(
        primary: Colors.blue,
        onPrimary: Colors.white,
        background: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        appBarBackground: Colors.white,
        appBarForeground: Colors.black,
        chatBubbleOutgoing: Colors.blue,
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Colors.white70,
        chatBubbleIncoming: Colors.grey,
        chatBubbleIncomingText: Colors.black,
        chatBubbleIncomingSubtext: Colors.black54,
        chatDateBadge: Colors.grey,
        chatDateBadgeText: Colors.white,
        chatBubbleOutgoingGradient: [Color(0xFFFF5E36), Color(0xFF9013FE), Color(0xFF2C3E50)],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatPreviewCard(
            theme: testTheme,
            height: 200,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(ChatPreviewCard), findsOneWidget);
  });

  testWidgets('Test ChatPreviewCard with 4-color gradient', (WidgetTester tester) async {
    const testTheme = TheavTheme(
      id: 'test_theme_4',
      name: 'Test 4',
      author: 'Tester',
      isDark: false,
      wallpaper: TheavWallpaper(type: 'color', backgroundColor: Colors.white),
      palette: TheavPalette(
        primary: Colors.blue,
        onPrimary: Colors.white,
        background: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        appBarBackground: Colors.white,
        appBarForeground: Colors.black,
        chatBubbleOutgoing: Colors.blue,
        chatBubbleOutgoingText: Colors.white,
        chatBubbleOutgoingSubtext: Colors.white70,
        chatBubbleIncoming: Colors.grey,
        chatBubbleIncomingText: Colors.black,
        chatBubbleIncomingSubtext: Colors.black54,
        chatDateBadge: Colors.grey,
        chatDateBadgeText: Colors.white,
        chatBubbleOutgoingGradient: [
          Color(0xFFFF007F),
          Color(0xFF7928CA),
          Color(0xFF00DFD8),
          Color(0xFF0088CC),
        ],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatPreviewCard(
            theme: testTheme,
            height: 200,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(ChatPreviewCard), findsOneWidget);
  });
}
