import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/voice_playback_service.dart';
import 'package:theaver/services/video_note_playback_service.dart';
import 'package:theaver/services/media_playback_coordinator.dart';
import 'package:theaver/widgets/chat/media_note_player_header.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/voice_message_widget.dart';
import 'package:theaver/l10n/app_localizations.dart';

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
          'chat_voice_message': 'Voice message',
          'chat_video_note': 'Video message',
          'chat_voice_speed': 'Speed',
          'chat_voice_hold_hint': 'Hold to record voice message',
          'chat_voice_swipe_cancel': 'Slide to cancel',
          'chat_voice_release_cancel': 'Release to cancel',
          'chat_voice_lock': 'Lock',
          'chat_voice_too_short': 'Hold to record voice message',
          'chat_voice_send': 'Send',
          'chat_voice_discard': 'Discard',
          'chat_voice_pause': 'Pause',
          'chat_voice_resume': 'Resume',
          'chat_voice_preview': 'Preview',
          'chat_voice_permission_denied': 'Microphone access denied',
        }),
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async => '/tmp',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (methodCall) async {
        if (methodCall.method == 'init') {
          return {'id': 'test_player'};
        }
        if (methodCall.method == 'load') {
          return {'duration': 10000000};
        }
        return {};
      },
    );
  });

  group('VoicePlaybackService Unit Tests', () {
    test('Initial properties and playback speed cycling', () {
      final service = VoicePlaybackService();
      expect(service.playbackSpeed, 1.0);

      service.cyclePlaybackSpeed();
      expect(service.playbackSpeed, 1.5);

      service.cyclePlaybackSpeed();
      expect(service.playbackSpeed, 2.0);

      service.cyclePlaybackSpeed();
      expect(service.playbackSpeed, 1.0);

      service.setPlaybackSpeed(1.5);
      expect(service.playbackSpeed, 1.5);
      service.setPlaybackSpeed(1.0);
    });

    test('Stop active voice resets state', () {
      final service = VoicePlaybackService();
      service.stopVoice();
      expect(service.activeMessageId, isNull);
      expect(service.activeAudioUrl, isNull);
      expect(service.hasActiveAudio, isFalse);
    });
  });

  group('VoiceMessageWidget Widget Tests', () {
    testWidgets('Renders incoming voice message correctly', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const VoiceMessageWidget(
            messageId: 'msg_voice_1',
            audioUrl: 'https://example.com/voice1.m4a',
            duration: Duration(seconds: 42),
            waveform: [5, 12, 28, 14, 8, 20, 31, 10],
            isMe: false,
            isRead: false,
            timeText: '12:34',
            senderName: 'Alice',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Download icon button for uncached remote voice note
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      // Duration text 0:42
      expect(find.text('0:42'), findsOneWidget);
      // Time text 12:34
      expect(find.text('12:34'), findsOneWidget);
      // CustomPaint for waveform scrubber
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('Renders outgoing voice message with checkmark status', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const VoiceMessageWidget(
            messageId: 'msg_voice_2',
            audioUrl: 'https://example.com/voice2.m4a',
            duration: Duration(seconds: 15),
            isMe: true,
            isRead: true,
            sendStatus: 1,
            timeText: '14:20',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.text('0:15'), findsOneWidget);
      expect(find.text('14:20'), findsOneWidget);
    });
  });

  group('MediaNotePlayerHeader Widget Tests', () {
    testWidgets('Hidden when no active voice or video is playing', (tester) async {
      VoicePlaybackService().stopVoice();
      VideoNotePlaybackService().stopActivePlayback();

      await tester.pumpWidget(
        createTestApp(
          const MediaNotePlayerHeader(),
        ),
      );
      await tester.pumpAndSettle();

      // Container should be empty (SizedBox.shrink)
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('MessageBubble Integration Tests', () {
    testWidgets('Renders voice message inside MessageBubble', (tester) async {
      final message = Message(
        id: 'voice_msg_3',
        chatId: 'chat_1',
        senderId: 'user_1',
        content: 'Voice message',
        messageType: 'voice',
        fileUrl: 'https://example.com/audio.m4a',
        fileName: 'audio.m4a',
        isEdited: false,
        createdAt: '2026-09-13T12:00:00Z',
        senderName: 'Bob',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'user_me',
            formatTime: (_) => '12:00',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // VoiceMessageWidget should be found
      expect(find.byType(VoiceMessageWidget), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });

    testWidgets('Renders voice message inside MessageBubble with waveform and duration', (tester) async {
      final message = Message(
        id: 'voice_msg_4',
        chatId: 'chat_1',
        senderId: 'user_1',
        content: 'Voice message',
        messageType: 'voice',
        fileUrl: 'https://example.com/audio4.m4a',
        fileName: 'audio4.m4a',
        duration: 35,
        waveform: [10, 20, 30, 25, 15, 5],
        isEdited: false,
        createdAt: '2026-09-13T12:00:00Z',
        senderName: 'Charlie',
      );

      await tester.pumpWidget(
        createTestApp(
          MessageBubble(
            message: message,
            isMe: false,
            currentUserId: 'user_me',
            formatTime: (_) => '12:00',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final voiceWidget = tester.widget<VoiceMessageWidget>(find.byType(VoiceMessageWidget));
      expect(voiceWidget.duration, const Duration(seconds: 35));
      expect(voiceWidget.waveform, [10, 20, 30, 25, 15, 5]);
      expect(find.text('0:35'), findsOneWidget);
    });
  });

  group('VideoNotePlaybackService Unit Tests', () {
    test('Stop active video note resets state', () {
      final service = VideoNotePlaybackService();
      service.stopActivePlayback();
      expect(service.activeMessageId, isNull);
      expect(service.activeVideoUrl, isNull);
      expect(service.hasActiveVideo, isFalse);
    });

    test('Video note playback speed cycling works correctly', () async {
      final service = VideoNotePlaybackService();
      await service.setPlaybackSpeed(1.0);
      expect(service.playbackSpeed, 1.0);

      await service.cyclePlaybackSpeed();
      expect(service.playbackSpeed, 1.5);

      await service.cyclePlaybackSpeed();
      expect(service.playbackSpeed, 2.0);

      await service.cyclePlaybackSpeed();
      expect(service.playbackSpeed, 1.0);
    });
  });

  group('MediaPlaybackCoordinator Unit Tests', () {
    test('Initial coordinator state is empty', () {
      final coordinator = MediaPlaybackCoordinator.instance;
      expect(coordinator.hasActiveMedia, isFalse);
      expect(coordinator.activeTrack, isNull);
      expect(coordinator.queue, isEmpty);
    });

    test('Cycle playback speed cycles across 1.0x, 1.5x, 2.0x and updates services', () async {
      final coordinator = MediaPlaybackCoordinator.instance;
      await coordinator.cyclePlaybackSpeed(); // might be at 1.0 -> 1.5
      expect([1.0, 1.5, 2.0], contains(coordinator.playbackSpeed));

      final speedBefore = coordinator.playbackSpeed;
      await coordinator.cyclePlaybackSpeed();
      final speedAfter = coordinator.playbackSpeed;
      expect(speedAfter != speedBefore, isTrue);

      expect(VoicePlaybackService().playbackSpeed, speedAfter);
      expect(VideoNotePlaybackService().playbackSpeed, speedAfter);
    });

    test('Queue progression and onTrackCompleted advances sequentially', () async {
      final coordinator = MediaPlaybackCoordinator.instance;
      final track1 = const PlaybackTrack(
        messageId: 'msg_track_1',
        chatId: 'chat_1',
        chatType: 'private',
        mediaType: 'voice',
        mediaUrl: '/tmp/nonexistent_audio1.m4a',
      );
      final track2 = const PlaybackTrack(
        messageId: 'msg_track_2',
        chatId: 'chat_1',
        chatType: 'private',
        mediaType: 'voice',
        mediaUrl: '/tmp/nonexistent_audio2.m4a',
      );

      await coordinator.startPlayback(
        track: track1,
        remainingQueue: [track2],
      );

      expect(coordinator.hasActiveMedia, isTrue);
      expect(coordinator.activeTrack?.messageId, 'msg_track_1');
      expect(coordinator.isVoice, isTrue);
      expect(coordinator.queue.length, 1);
      expect(coordinator.queue.first.messageId, 'msg_track_2');

      // Complete track 1 -> auto-advances to track 2
      await coordinator.onTrackCompleted('msg_track_1');
      expect(coordinator.hasActiveMedia, isTrue);
      expect(coordinator.activeTrack?.messageId, 'msg_track_2');
      expect(coordinator.isVoice, isTrue);
      expect(coordinator.queue, isEmpty);

      // Stop all clears coordinator
      await coordinator.stopAll();
      expect(coordinator.hasActiveMedia, isFalse);
      expect(coordinator.activeTrack, isNull);
    });

    test('onBuildPlaylistRequested is called when startPlayback has no explicit queue', () async {
      final coordinator = MediaPlaybackCoordinator.instance;
      final track1 = const PlaybackTrack(
        messageId: 'msg_a',
        chatId: 'chat_test',
        chatType: 'group',
        mediaType: 'voice',
        mediaUrl: '/tmp/nonexistent_a.m4a',
      );
      final track2 = const PlaybackTrack(
        messageId: 'msg_b',
        chatId: 'chat_test',
        chatType: 'group',
        mediaType: 'voice',
        mediaUrl: '/tmp/nonexistent_b.m4a',
      );

      coordinator.onBuildPlaylistRequested = (id) {
        if (id == 'msg_a') return [track2];
        return [];
      };

      await coordinator.startPlayback(track: track1);
      expect(coordinator.queue.length, 1);
      expect(coordinator.queue.first.messageId, 'msg_b');

      await coordinator.stopAll();
      coordinator.onBuildPlaylistRequested = null;
    });
  });
}
