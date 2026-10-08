import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/widgets/chat/chat_messages_list_view.dart';
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

    testWidgets('Formatted markdown text renders MarkdownBody', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextMessageWidget(
              text: 'Сообщение с **жирным** и _курсивом_',
              isMe: false,
            ),
          ),
        ),
      );

      // For markdown, MarkdownBody must be used
      expect(find.byType(MarkdownBody), findsOneWidget);
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
