import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/video_note_recorder_service.dart';
import 'package:theaver/widgets/chat/liquid_glass_input_field.dart';
import 'package:theaver/widgets/chat/round_video_recording_overlay.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/video_message_widget.dart';
import 'package:theaver/widgets/chat/round_video_thumbnail.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:video_player/video_player.dart';
import 'package:theaver/services/video_note_playback_service.dart';
import 'package:theaver/widgets/chat/message_context_menu.dart';
import 'package:provider/provider.dart';
import 'package:theaver/services/profile_theme_provider.dart';

class _TestAppLocalizations extends AppLocalizations {
  final Map<String, String> translations;
  _TestAppLocalizations(Locale locale, this.translations) : super(locale);

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
  Future<AppLocalizations> load(Locale locale) async {
    return _TestAppLocalizations(locale, translations);
  }

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

Widget createTestApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileThemeProvider>(
        create: (_) => ProfileThemeProvider(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate({
          'chat_video_note': 'Video message',
          'chat_video_note_hold_hint': 'Hold to record video',
          'chat_video_note_swipe_cancel': 'Slide to cancel',
          'chat_video_note_release_cancel': 'Release to cancel',
          'chat_video_note_lock': 'Lock',
          'chat_video_note_too_short': 'Hold to record video. Tap to switch to voice.',
          'chat_video_note_send': 'Send',
          'chat_video_note_discard': 'Discard',
          'chat_video_note_flip_camera': 'Flip camera',
          'chat_video_note_stop': 'Stop',
          'chat_video_note_tap_switch': 'Tap to switch to video',
          'chat_video_note_tap_voice': 'Tap to switch to voice',
          'chat_video_note_permission_denied': 'Camera or microphone access denied',
          'chat_edited': 'edited',
          'chat_action_reply': 'Reply',
          'chat_action_copy': 'Copy',
          'chat_action_pin': 'Pin',
          'chat_action_delete': 'Delete',
          'chat_edit_message': 'Edit',
          'format_quote': 'Quote',
          'chat_reply_you': 'Вы',
        }),
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VisibilityDetectorController.instance.updateInterval = Duration.zero;

  group('VideoNoteRecorderService Unit Tests', () {
    test('Initial properties are correct', () {
      final service = VideoNoteRecorderService();
      expect(service.isRecording, isFalse);
      expect(service.isInitialized, isFalse);
      expect(service.isFrontCamera, isTrue);
      expect(service.elapsed, Duration.zero);
      expect(service.renderer, isNull);
      expect(service.errorMessage, isNull);
    });

    test('Permission helpers on non-mobile test runner return expected defaults', () async {
      final service = VideoNoteRecorderService();
      // In flutter test environment (Linux/desktop), hasPermissions returns true by default
      final hasPerm = await service.hasPermissions();
      expect(hasPerm, isTrue);

      final permDenied = await service.isPermanentlyDenied();
      expect(permDenied, isFalse);
    });

    test('Zoom level state and clamping in VideoNoteRecorderService', () async {
      final service = VideoNoteRecorderService();
      expect(service.zoomLevel, equals(1.0));

      await service.setZoom(2.5);
      expect(service.zoomLevel, equals(2.5));

      // Clamping upper bound
      await service.setZoom(5.0);
      expect(service.zoomLevel, equals(3.0));

      // Clamping lower bound
      await service.setZoom(0.5);
      expect(service.zoomLevel, equals(1.0));
    });
  });

  group('RoundVideoRecordingOverlay Widget Tests', () {
    testWidgets('Renders BackdropFilter, circular viewfinder, timer, and slide hint',
        (WidgetTester tester) async {
      final recorderService = VideoNoteRecorderService();
      bool cancelled = false;
      bool sent = false;
      bool tooShort = false;

      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            recorderService: recorderService,
            onCancel: () => cancelled = true,
            onSend: (_) => sent = true,
            onTooShort: () => tooShort = true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Cinematic backdrop blur
      expect(find.byType(BackdropFilter), findsOneWidget);

      // 2. Circular camera viewfinder
      expect(find.byType(ClipOval), findsAtLeastNWidgets(1));

      // 3. Timer badge (initial 0:00)
      expect(find.text('0:00'), findsOneWidget);

      // 4. Slide to cancel hint
      expect(find.text('Slide to cancel'), findsOneWidget);
      expect(find.byType(iconoir.NavArrowLeft), findsOneWidget);

      // 5. Lock indicator
      expect(find.byType(iconoir.Lock), findsOneWidget);
      expect(find.byType(iconoir.NavArrowUp), findsOneWidget);

      expect(cancelled, isFalse);
      expect(sent, isFalse);
      expect(tooShort, isFalse);
    });

    testWidgets('Swipe up locks recording and reveals hands-free control bar',
        (WidgetTester tester) async {
      final recorderService = VideoNoteRecorderService();
      final overlayKey = GlobalKey();

      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            key: overlayKey,
            recorderService: recorderService,
            onCancel: () {},
            onSend: (_) {},
            onTooShort: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Initially hands-free buttons (Trash, Refresh/Flip, SendSolid) are not shown
      expect(find.byType(iconoir.Trash), findsNothing);
      expect(find.byType(iconoir.Refresh), findsNothing);
      expect(find.byType(iconoir.SendSolid), findsNothing);

      // Simulate dragging up beyond threshold (-75)
      final state = overlayKey.currentState as dynamic;
      state.updatePointerOffset(0.0, -80.0);
      await tester.pump(const Duration(milliseconds: 300));

      // Now hands-free controls are rendered
      expect(find.byType(iconoir.Trash), findsOneWidget);
      expect(find.byType(iconoir.Refresh), findsOneWidget);
      expect(find.byType(iconoir.SendSolid), findsOneWidget);
    });

    testWidgets('Renders zoom badge and allows cycling zoom presets on tap',
        (WidgetTester tester) async {
      final recorderService = VideoNoteRecorderService();

      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            recorderService: recorderService,
            onCancel: () {},
            onSend: (_) {},
            onTooShort: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Verify zoom badge starts at 1.0x
      expect(find.text('1.0x'), findsOneWidget);

      // Tap zoom badge -> cycles to 2.0x
      await tester.tap(find.text('1.0x'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('2.0x'), findsOneWidget);
      expect(recorderService.zoomLevel, equals(2.0));

      // Tap zoom badge -> cycles to 3.0x
      await tester.tap(find.text('2.0x'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('3.0x'), findsOneWidget);
      expect(recorderService.zoomLevel, equals(3.0));

      // Tap zoom badge -> cycles back to 1.0x
      await tester.tap(find.text('3.0x'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('1.0x'), findsOneWidget);
      expect(recorderService.zoomLevel, equals(1.0));
    });

    testWidgets('Drag up past lock threshold adjusts zoom level',
        (WidgetTester tester) async {
      final recorderService = VideoNoteRecorderService();
      final overlayKey = GlobalKey();

      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            key: overlayKey,
            recorderService: recorderService,
            onCancel: () {},
            onSend: (_) {},
            onTooShort: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final state = overlayKey.currentState as dynamic;
      // Drag up to lock (-70)
      state.updatePointerOffset(0.0, -70.0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.currentZoom, equals(1.0));

      // Drag up further (-145 -> halfway between 70 and 220)
      state.updatePointerOffset(0.0, -145.0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.currentZoom, closeTo(2.0, 0.1));

      // Drag up to max zoom (-220)
      state.updatePointerOffset(0.0, -220.0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.currentZoom, equals(3.0));
      expect(find.text('3.0x'), findsOneWidget);
    });
  });

  group('VideoMessageWidget Tests', () {
    testWidgets('Renders circular container with duration pill on left and time pill on right',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const VideoMessageWidget(
            videoUrl: 'https://example.com/video_note.mp4',
            size: 240.0,
            isMe: true,
            isRead: true,
            sendStatus: 1,
            timeText: '14:22',
            duration: Duration(seconds: 15),
          ),
        ),
      );
      await tester.pump();

      // Circular video container with ClipOval
      expect(find.byType(ClipOval), findsOneWidget);

      // Duration pill displays video duration
      expect(find.text('0:15'), findsOneWidget);

      // Time pill displays message time
      expect(find.text('14:22'), findsOneWidget);

      // Outgoing status for read message (DoubleCheck)
      expect(find.byType(iconoir.DoubleCheck), findsOneWidget);
    });

    testWidgets('Renders refresh retry button on error and resets error state on tap',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const VideoMessageWidget(
            videoUrl: '', // empty url triggers error state
            size: 240.0,
            isMe: false,
            isRead: false,
            sendStatus: 1,
            timeText: '14:22',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In error state, refresh icon must be shown
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Tapping refresh icon attempts recovery and does not crash
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
    });
  });

  group('MessageBubble Round Video Integration Tests', () {
    testWidgets('Renders VideoMessageWidget with transparent background for round message',
        (WidgetTester tester) async {
      final roundMessage = Message(
        id: 'msg-round-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'video_note.mp4',
        messageType: 'round',
        fileUrl: 'https://example.com/video_note.mp4',
        fileName: 'video_note.mp4',
        isRound: true,
        isEdited: false,
        senderName: 'Alice',
        createdAt: '2026-09-12T10:00:00Z',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: roundMessage,
            isMe: false,
            currentUserId: 'user-2',
            formatTime: (_) => '10:00',
          ),
        ),
      );
      await tester.pump();

      // Must render VideoMessageWidget
      expect(find.byType(VideoMessageWidget), findsOneWidget);

      // Find Container that wraps the bubbleCore
      final containers = tester.widgetList<Container>(find.byType(Container));
      final bubbleContainer = containers.firstWhere(
        (c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).color == Colors.transparent,
      );
      expect(bubbleContainer, isNotNull);
    });

    testWidgets('Suppresses caption text for round video messages even if content is set',
        (WidgetTester tester) async {
      final roundMessage = Message(
        id: 'msg-round-2',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'Видеосообщение',
        messageType: 'video',
        fileUrl: 'https://example.com/video_note.mp4',
        fileName: 'video_note.mp4',
        isRound: true,
        isEdited: false,
        senderName: 'Alice',
        createdAt: '2026-09-12T10:00:00Z',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: roundMessage,
            isMe: false,
            currentUserId: 'user-2',
            formatTime: (_) => '10:00',
          ),
        ),
      );
      await tester.pump();

      // VideoMessageWidget must be rendered
      expect(find.byType(VideoMessageWidget), findsOneWidget);

      // In-chat caption text "Видеосообщение" must NOT be rendered
      expect(find.text('Видеосообщение'), findsNothing);
    });
  });

  group('RoundVideoThumbnail Tests', () {
    testWidgets('Renders ClipOval with ImageFiltered blur and play icon',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          const RoundVideoThumbnail(
            videoUrl: 'https://example.com/video_note.mp4',
            size: 18.0,
          ),
        ),
      );
      await tester.pump();

      // Renders circular clip
      expect(find.byType(ClipOval), findsOneWidget);

      // Renders ImageFiltered for blur effect
      expect(find.byType(ImageFiltered), findsOneWidget);

      // Renders centered play icon
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('LiquidGlassInputField Media Mode Tests', () {
    testWidgets('Shows microphone when empty and toggles to video camera on tap',
        (WidgetTester tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        createTestApp(
          LiquidGlassInputField(
            enabled: false,
            controller: controller,
            hintText: 'Message',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially microphone icon is visible
      expect(find.byType(iconoir.MicrophoneSolid), findsOneWidget);
      expect(find.byType(iconoir.VideoCamera), findsNothing);

      // Tap on the media button to toggle
      await tester.tap(find.byType(iconoir.MicrophoneSolid));
      await tester.pumpAndSettle();

      // Now video camera icon is visible
      expect(find.byType(iconoir.VideoCamera), findsOneWidget);
    });
  });

  group('RoundVideoRecordingOverlay Reply Integration Tests', () {
    testWidgets('Renders reply banner when replyToMessage is provided',
        (WidgetTester tester) async {
      final recorderService = VideoNoteRecorderService();
      final replyMsg = Message(
        id: 'msg-reply-1',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'Original message content',
        senderName: 'Bob',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-09-12T10:00:00Z',
      );

      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            recorderService: recorderService,
            onCancel: () {},
            onSend: (_) {},
            onTooShort: () {},
            replyToMessage: replyMsg,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Original message content'), findsOneWidget);
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    });
  });

  group('MessageBubble Round Video Reply Tests', () {
    testWidgets('Renders reply preview above round video when message has reply',
        (WidgetTester tester) async {
      final roundMessageWithReply = Message(
        id: 'msg-round-2',
        chatId: 'chat-1',
        senderId: 'user-1',
        content: 'video_note.mp4',
        messageType: 'round',
        fileUrl: 'https://example.com/video_note.mp4',
        isRound: true,
        isEdited: false,
        senderName: 'Alice',
        createdAt: '2026-09-12T10:00:00Z',
        replyToMessageId: 'orig-1',
        replyInfo: const ReplyInfo(
          messageId: 'orig-1',
          senderId: 'user-2',
          senderName: 'Charlie',
          content: 'Quoted text here',
          messageType: 'text',
        ),
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: roundMessageWithReply,
            isMe: true,
            currentUserId: 'user-1',
            formatTime: (_) => '10:05',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('Quoted text here', findRichText: true), findsOneWidget);
      expect(find.byType(ClipOval), findsOneWidget);
    });
  });

  group('MessageContextMenu Restriction Tests', () {
    testWidgets('Suppresses edit and quote when onEdit and onQuote are null',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        createTestApp(
          MessageContextMenu(
            messageOffset: Offset.zero,
            messageSize: const Size(200, 50),
            isMe: true,
            onReply: () {},
            onQuote: null,
            onEdit: null,
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onReaction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Quote'), findsNothing);
    });
  });

  group('VideoNotePlaybackService Unit Tests', () {
    test('Playback service manages active state, floating and auto-advancing', () {
      final service = VideoNotePlaybackService();
      bool nextRequested = false;
      service.onPlayNextRequested = (_) => nextRequested = true;

      service.setActivePlayback(
        messageId: 'note-1',
        videoUrl: 'https://example.com/v1.mp4',
        controller: VideoPlayerController.networkUrl(Uri.parse('https://example.com/v1.mp4')),
      );

      expect(service.activeMessageId, equals('note-1'));
      expect(service.isInView, isTrue);
      expect(service.isFloating, isFalse);

      service.setInView('note-1', false);
      expect(service.isFloating, isTrue);

      service.onVideoCompleted('note-1');
      expect(nextRequested, isTrue);

      service.stopActivePlayback();
      expect(service.activeMessageId, isNull);
      expect(service.isFloating, isFalse);
    });

    test('Playback service automatically enters floating mode if next video note is not in view', () {
      final service = VideoNotePlaybackService();

      // Screen is populated with note-1 in view
      service.setInView('note-1', true);
      expect(service.isMessageInView('note-1'), isTrue);
      expect(service.isMessageInView('note-2'), isFalse);

      // Playing note-2 (off-screen)
      service.setActivePlayback(
        messageId: 'note-2',
        videoUrl: 'https://example.com/v2.mp4',
        controller: VideoPlayerController.networkUrl(Uri.parse('https://example.com/v2.mp4')),
      );

      // Must start in floating PiP mode immediately
      expect(service.activeMessageId, equals('note-2'));
      expect(service.isInView, isFalse);
      expect(service.isFloating, isTrue);

      service.stopActivePlayback();
    });

    test('Preserves floating mode when auto-advancing to next note while scrolled away (even with empty visibleMessageIds)', () {
      final service = VideoNotePlaybackService();
      service.stopActivePlayback();
      service.clearVisibility();

      // Start playing note-1
      service.setActivePlayback(
        messageId: 'note-1',
        videoUrl: 'https://example.com/v1.mp4',
        controller: VideoPlayerController.networkUrl(Uri.parse('https://example.com/v1.mp4')),
        initialInView: true,
      );
      expect(service.isFloating, isFalse);

      // User scrolls note-1 out of view (e.g. no video notes visible in viewport now)
      service.setInView('note-1', false);
      expect(service.isFloating, isTrue);

      // Auto-advance triggers for note-2 which is also off-screen
      service.setActivePlayback(
        messageId: 'note-2',
        videoUrl: 'https://example.com/v2.mp4',
        controller: VideoPlayerController.networkUrl(Uri.parse('https://example.com/v2.mp4')),
      );

      // Must remain floating in PiP mode without glitching or dismissing
      expect(service.activeMessageId, equals('note-2'));
      expect(service.isFloating, isTrue);
      expect(service.isInView, isFalse);

      // If user scrolls back so note-2 becomes visible in viewport
      service.setInView('note-2', true);
      expect(service.isFloating, isFalse);
      expect(service.isInView, isTrue);

      service.stopActivePlayback();
    });

    test('Floating PiP switches back to in-view when advancing to a note that is visible on screen', () {
      final service = VideoNotePlaybackService();
      service.stopActivePlayback();
      service.clearVisibility();

      // note-2 is in view on screen, but note-1 was scrolled out
      service.setInView('note-2', true);

      service.setActivePlayback(
        messageId: 'note-1',
        videoUrl: 'https://example.com/v1.mp4',
        controller: VideoPlayerController.networkUrl(Uri.parse('https://example.com/v1.mp4')),
        initialInView: false,
      );
      expect(service.isFloating, isTrue);

      // Advancing to note-2 which is in view
      service.setActivePlayback(
        messageId: 'note-2',
        videoUrl: 'https://example.com/v2.mp4',
        controller: VideoPlayerController.networkUrl(Uri.parse('https://example.com/v2.mp4')),
        initialInView: service.isMessageInView('note-2'),
      );

      expect(service.activeMessageId, equals('note-2'));
      expect(service.isFloating, isFalse);
      expect(service.isInView, isTrue);

      service.stopActivePlayback();
    });
  });

  group('Circular Scrubbing Geometry and Calculation Tests', () {
    test('Calculates clockwise progress correctly starting from 12 o\'clock', () {
      const center = Offset(100, 100);

      // 12 o'clock (top) -> 0.0
      const top = Offset(100, 0);
      final angleTop = math.atan2(top.dy - center.dy, top.dx - center.dx);
      var normTop = angleTop + math.pi / 2;
      while (normTop < 0) {
        normTop += 2 * math.pi;
      }
      while (normTop >= 2 * math.pi) {
        normTop -= 2 * math.pi;
      }
      final progressTop = (normTop / (2 * math.pi)).clamp(0.0, 1.0);
      expect(progressTop, closeTo(0.0, 0.001));

      // 3 o'clock (right) -> 0.25
      const right = Offset(200, 100);
      final angleRight = math.atan2(right.dy - center.dy, right.dx - center.dx);
      var normRight = angleRight + math.pi / 2;
      while (normRight < 0) {
        normRight += 2 * math.pi;
      }
      while (normRight >= 2 * math.pi) {
        normRight -= 2 * math.pi;
      }
      final progressRight = (normRight / (2 * math.pi)).clamp(0.0, 1.0);
      expect(progressRight, closeTo(0.25, 0.001));

      // 6 o'clock (bottom) -> 0.5
      const bottom = Offset(100, 200);
      final angleBottom = math.atan2(bottom.dy - center.dy, bottom.dx - center.dx);
      var normBottom = angleBottom + math.pi / 2;
      while (normBottom < 0) {
        normBottom += 2 * math.pi;
      }
      while (normBottom >= 2 * math.pi) {
        normBottom -= 2 * math.pi;
      }
      final progressBottom = (normBottom / (2 * math.pi)).clamp(0.0, 1.0);
      expect(progressBottom, closeTo(0.5, 0.001));

      // 9 o'clock (left) -> 0.75
      const left = Offset(0, 100);
      final angleLeft = math.atan2(left.dy - center.dy, left.dx - center.dx);
      var normLeft = angleLeft + math.pi / 2;
      while (normLeft < 0) {
        normLeft += 2 * math.pi;
      }
      while (normLeft >= 2 * math.pi) {
        normLeft -= 2 * math.pi;
      }
      final progressLeft = (normLeft / (2 * math.pi)).clamp(0.0, 1.0);
      expect(progressLeft, closeTo(0.75, 0.001));
    });
  });
}
