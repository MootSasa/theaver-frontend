import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/services/video_note_recorder_service.dart';
import 'package:theaver/services/voice_note_recorder_service.dart';
import 'package:theaver/widgets/chat/round_video_recording_overlay.dart';
import 'package:theaver/widgets/chat/voice_recording_overlay.dart';

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
          'chat_voice_swipe_cancel': 'Slide to cancel',
          'chat_voice_too_short': 'Hold to record voice message',
          'chat_video_note_swipe_cancel': 'Slide to cancel',
          'chat_video_note_too_short': 'Hold to record video',
        }),
      ],
      home: Scaffold(body: child),
    ),
  );
}

class FakeVoiceNoteRecorderService extends VoiceNoteRecorderService {
  bool _mockRecording = false;
  Duration _mockElapsed = Duration.zero;
  bool cancelCalled = false;
  File? tempFile;

  @override
  bool get isRecording => _mockRecording;

  @override
  Duration get elapsed => _mockElapsed;

  void setMockRecording(bool value, {File? file, Duration? elapsed}) {
    _mockRecording = value;
    tempFile = file;
    if (elapsed != null) {
      _mockElapsed = elapsed;
    }
    notifyListeners();
  }

  @override
  Future<void> cancelRecording() async {
    cancelCalled = true;
    _mockRecording = false;
    _mockElapsed = Duration.zero;
    if (tempFile != null && tempFile!.existsSync()) {
      try {
        tempFile!.deleteSync();
      } catch (_) {}
    }
    notifyListeners();
  }
}

class FakeVideoNoteRecorderService extends VideoNoteRecorderService {
  bool _mockRecording = false;
  Duration _mockElapsed = Duration.zero;
  bool cancelCalled = false;
  File? tempFile;

  @override
  bool get isRecording => _mockRecording;

  @override
  Duration get elapsed => _mockElapsed;

  void setMockRecording(bool value, {File? file, Duration? elapsed}) {
    _mockRecording = value;
    tempFile = file;
    if (elapsed != null) {
      _mockElapsed = elapsed;
    }
    notifyListeners();
  }

  @override
  Future<void> cancelRecording() async {
    cancelCalled = true;
    _mockRecording = false;
    _mockElapsed = Duration.zero;
    if (tempFile != null && tempFile!.existsSync()) {
      try {
        tempFile!.deleteSync();
      } catch (_) {}
    }
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async => Directory.systemTemp.path,
    );
  });

  group('Voice Recording Overlay Teardown & Lifecycle Tests', () {
    testWidgets('Unmounting VoiceRecordingOverlay automatically cancels active recording',
        (tester) async {
      final fakeService = FakeVoiceNoteRecorderService();
      final tempFile = File('${Directory.systemTemp.path}/test_voice_cleanup_${DateTime.now().millisecondsSinceEpoch}.m4a');
      tempFile.writeAsStringSync('dummy voice content');
      expect(tempFile.existsSync(), isTrue);

      fakeService.setMockRecording(true, file: tempFile);

      bool cancelled = false;
      bool sent = false;
      bool tooShort = false;

      // Mount overlay
      await tester.pumpWidget(
        createTestApp(
          VoiceRecordingOverlay(
            recorderService: fakeService,
            onCancel: () => cancelled = true,
            onSend: (_) => sent = true,
            onTooShort: () => tooShort = true,
          ),
        ),
      );
      await tester.pump();

      expect(fakeService.cancelCalled, isFalse);
      expect(tempFile.existsSync(), isTrue);

      // Now unmount overlay (e.g. back navigation or chat screen popped)
      await tester.pumpWidget(createTestApp(const SizedBox()));
      await tester.pump();

      // VoiceRecordingOverlay.dispose() should have called cancelRecording()
      expect(fakeService.cancelCalled, isTrue);
      expect(fakeService.isRecording, isFalse);
      expect(tempFile.existsSync(), isFalse);
      expect(cancelled, isFalse);
      expect(sent, isFalse);
      expect(tooShort, isFalse);
    });

    testWidgets('VoiceRecordingOverlay short release (< 1s) triggers onTooShort and deletes file',
        (tester) async {
      final fakeService = FakeVoiceNoteRecorderService();
      final tempFile = File('${Directory.systemTemp.path}/test_voice_short_${DateTime.now().millisecondsSinceEpoch}.m4a');
      tempFile.writeAsStringSync('short voice content');
      expect(tempFile.existsSync(), isTrue);

      fakeService.setMockRecording(true, file: tempFile, elapsed: const Duration(milliseconds: 300));

      bool cancelled = false;
      bool tooShort = false;
      final key = GlobalKey<VoiceRecordingOverlayState>();

      await tester.pumpWidget(
        createTestApp(
          VoiceRecordingOverlay(
            key: key,
            recorderService: fakeService,
            onCancel: () => cancelled = true,
            onSend: (_) {},
            onTooShort: () => tooShort = true,
          ),
        ),
      );
      await tester.pump();

      key.currentState?.handlePointerUp();
      await tester.pump();

      expect(tooShort, isTrue);
      expect(cancelled, isTrue);
      expect(fakeService.cancelCalled, isTrue);
      expect(tempFile.existsSync(), isFalse);
    });
  });

  group('Round Video Recording Overlay Teardown & Lifecycle Tests', () {
    testWidgets('Unmounting RoundVideoRecordingOverlay automatically cancels active recording',
        (tester) async {
      final fakeService = FakeVideoNoteRecorderService();
      final tempFile = File('${Directory.systemTemp.path}/test_video_cleanup_${DateTime.now().millisecondsSinceEpoch}.mp4');
      tempFile.writeAsStringSync('dummy video content');
      expect(tempFile.existsSync(), isTrue);

      fakeService.setMockRecording(true, file: tempFile);

      bool cancelled = false;
      bool sent = false;
      bool tooShort = false;

      // Mount overlay
      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            recorderService: fakeService,
            onCancel: () => cancelled = true,
            onSend: (_) => sent = true,
            onTooShort: () => tooShort = true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(fakeService.cancelCalled, isFalse);
      expect(tempFile.existsSync(), isTrue);

      // Now unmount overlay (e.g. back navigation or chat screen popped)
      await tester.pumpWidget(createTestApp(const SizedBox()));
      await tester.pump(const Duration(milliseconds: 200));

      // RoundVideoRecordingOverlay.dispose() should have called cancelRecording()
      expect(fakeService.cancelCalled, isTrue);
      expect(fakeService.isRecording, isFalse);
      expect(tempFile.existsSync(), isFalse);
      expect(cancelled, isFalse);
      expect(sent, isFalse);
      expect(tooShort, isFalse);
    });

    testWidgets('RoundVideoRecordingOverlay short release (< 1s) triggers onTooShort and deletes file',
        (tester) async {
      final fakeService = FakeVideoNoteRecorderService();
      final tempFile = File('${Directory.systemTemp.path}/test_video_short_${DateTime.now().millisecondsSinceEpoch}.mp4');
      tempFile.writeAsStringSync('short video content');
      expect(tempFile.existsSync(), isTrue);

      fakeService.setMockRecording(true, file: tempFile, elapsed: const Duration(milliseconds: 400));

      bool tooShort = false;
      final key = GlobalKey();

      await tester.pumpWidget(
        createTestApp(
          RoundVideoRecordingOverlay(
            key: key,
            recorderService: fakeService,
            onCancel: () {},
            onSend: (_) {},
            onTooShort: () => tooShort = true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final state = key.currentState as dynamic;
      state.handlePointerUp();
      await tester.pump();

      expect(tooShort, isTrue);
      expect(fakeService.cancelCalled, isTrue);
      expect(tempFile.existsSync(), isFalse);
    });
  });

  group('Recorder Services Direct Teardown Tests', () {
    test('VoiceNoteRecorderService dispose cleans up resources safely', () {
      final service = VoiceNoteRecorderService();
      expect(service.isRecording, isFalse);
      expect(service.isLocked, isFalse);
      expect(service.elapsed, Duration.zero);

      // Calling dispose when idle should complete cleanly without error
      service.dispose();
    });

    test('VideoNoteRecorderService cancelRecording resets state and zoom', () async {
      final service = VideoNoteRecorderService();
      await service.setZoom(2.5);
      expect(service.zoomLevel, equals(2.5));

      await service.cancelRecording();
      expect(service.isRecording, isFalse);
      expect(service.elapsed, Duration.zero);
      expect(service.zoomLevel, equals(1.0));

      service.dispose();
    });
  });
}
